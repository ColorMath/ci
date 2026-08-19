# colormath

[![CI](https://github.com/ColorMath/ci/actions/workflows/ci.yml/badge.svg)](https://github.com/ColorMath/ci/actions/workflows/ci.yml)

**Sixteen CI quality gates for Python web apps, in one `uses:` line.**

colormath is a reusable GitHub Actions workflow (plus the scripts and composite
actions behind it) that gives a Poetry-managed Python project a complete,
parallel CI gate suite: formatting, lint (Python and JS), types, docstrings,
alembic migration sync, import boundaries, tests, template lint, security,
secrets, accessibility, dependency CVEs (Python and JS), Dockerfile lint, and
per-change test coverage.

It grew out of a family of FastAPI + Poetry + Jinja/Tailwind apps deployed on
Cloud Run, but the gates apply to most Poetry projects — the JS-based gates
(frontend tests, JS lint, CSS lint, template accessibility) are driven by npm
scripts you define, and any gate can be switched off.

## Quick start

Create `.github/workflows/gates.yml` in your repo:

```yaml
name: Gates

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  gates:
    uses: ColorMath/ci/.github/workflows/gates.yml@vX.Y.Z   # latest: /releases/latest
    with:
      python-version: "3.12"
      default-branch: main
```

Open a pull request and you'll get sixteen parallel checks, each posting a
compact stats block to the run summary. Project-specific jobs (deploys,
previews, seeding) stay in your repo as siblings that gate on the suite:

```yaml
  deploy-staging:
    needs: gates
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    # ... your deploy steps, unchanged
```

The [example/](example/) directory is a minimal compliant consumer — start
there to see every contract file in place. colormath's own CI runs the full
suite against it on every PR.

## The gates

| Gate | Tool | Enforces |
|---|---|---|
| `ruff` | [ruff](https://docs.astral.sh/ruff/) | formatting + lint |
| `tests` | vitest + pytest | `poetry.lock` in sync with pyproject, then JS and Python suites green |
| `typecheck` | [mypy](https://mypy-lang.org/) | type checks pass |
| `docstrings` | [interrogate](https://interrogate.readthedocs.io/) | docstring coverage ≥ your `[tool.interrogate]` fail-under |
| `migrations` | git (no deps) | branch not missing alembic migrations that landed on the base branch (set `enable-migrations: false` without alembic) |
| `import-linter` | [import-linter](https://import-linter.readthedocs.io/) | your `[tool.importlinter]` import contracts hold (layers / forbidden / independence); set `enable-import-linter: false` until you write contracts |
| `jslint` | [eslint](https://eslint.org/) | hand-written JS passes lint |
| `styles` | [stylelint](https://stylelint.io/) | design tokens only — no hardcoded colors/font-sizes |
| `templates` | [djlint](https://djlint.com/) | Jinja templates are well-formed (per `[tool.djlint]`) |
| `sast` | [bandit](https://bandit.readthedocs.io/) | no Medium+ security findings in app source |
| `secrets` | [gitleaks](https://github.com/gitleaks/gitleaks) | no secrets anywhere in git history |
| `a11y` | [html-validate](https://html-validate.org/) | templates pass the a11y preset |
| `deps` | [pip-audit](https://pypi.org/project/pip-audit/) | locked, shipped deps have no actionable CVEs |
| `js-deps` | npm audit | locked, shipped JS deps have no high+ CVEs |
| `dockerfile` | [hadolint](https://github.com/hadolint/hadolint) | Dockerfile best practices |
| `diff-coverage` | [diff-cover](https://github.com/Bachmann1234/diff_cover) | changed lines ≥90% covered |

Two design choices worth calling out:

- **`diff-coverage`, not total coverage.** The gate requires the lines you
  *changed* to be covered. It never fails on pre-existing untested code, so
  you can adopt it on day one of a legacy codebase and ratchet quality up one
  PR at a time.
- **`deps` and `js-deps` audit what ships.** Locked versions are exported
  from `poetry.lock` for the production dependency groups only, and npm audit
  runs with `--omit=dev` — dev tooling never triggers a CVE failure, and
  local runs audit exactly what CI audits.
- **`deps` skips PRs that don't move dependencies.** The scan is ~200
  sequential PyPI lookups (minutes, against a suite where everything else
  finishes in ~2), and its verdict can only change when the locked set, the
  allowlist, or the upstream advisory databases move. So on a `pull_request`
  that touches none of `poetry.lock`, `pyproject.toml`, or
  `.colormath/audit.conf`, it reports green without scanning. Every other
  event — including each push to the default branch — scans in full, so
  newly-published advisories still surface on merge; add a `schedule:`
  trigger to your caller if you also want a nightly re-check. Opt out with
  `deps-skip-unchanged: false`. `make audit` always scans in full.
- **`migrations` catches alembic divergence before the merge.** A PR that
  branched before newer migrations landed on the base branch merges into
  multiple alembic heads. The gate diffs the base branch against the PR's
  merge-base, scoped to `migrations-path`, and fails with "pull in the latest
  `<branch>`" when the base moved. The base branch is your `default-branch`
  input when set, else discovered from the repo — main and master both just
  work.
- **`import-linter` enforces the architecture you write down.** The gate runs
  `lint-imports` against the contracts in your `[tool.importlinter]` — a
  layered dependency order, a module that must stay independent of another, a
  boundary a subsystem may not cross. Like the rest of the suite it needs no
  project deps (grimp builds the import graph by static analysis), and the
  rules are entirely yours: colormath ships the runner, your pyproject ships
  the contracts. Handy for invariants a reviewer can't reliably catch by eye —
  e.g. a worker entrypoint that must never import a FastAPI-coupled module.

## Adopting incrementally

Every gate has an `enable-<gate>` input (default `true`). On a codebase with
existing findings, land the caller with the failing gates disabled, burn the
findings down, and enable them one by one:

```yaml
    uses: ColorMath/ci/.github/workflows/gates.yml@vX.Y.Z   # latest: /releases/latest
    with:
      python-version: "3.12"
      default-branch: main
      enable-a11y: false           # TODO: burn down template findings
      enable-diff-coverage: false  # TODO: enable once the suite measures coverage
```

Disabled gates show as *skipped* in the run — visible, never silently absent.

## Configuration

### Workflow inputs

All inputs are optional.

| Input | Default | Purpose |
|---|---|---|
| `python-version` | `"3.12"` | Python for all Python gates |
| `node-version` | `"22"` | Node for all JS gates (html-validate 11.x needs ≥22) |
| `default-branch` | repo default | Base branch for diff-coverage |
| `workdir` | `"."` | Directory containing the app, for monorepos |
| `poetry-install-args` | `""` | Extra `poetry install` args, e.g. `"--with webapp,worker"` |
| `ruff-spec` | `"ruff>=0.14,<0.15"` | pip spec for ruff — match your pyproject pin |
| `ruff-select` | `""` (full lint) | Restrict `ruff check` to specific rules, e.g. `"I"` |
| `bandit-spec` | `"bandit>=1.9,<2"` | pip spec for bandit — match your pyproject pin |
| `interrogate-spec` | `"interrogate>=1.7,<2"` | pip spec for interrogate — match your pyproject pin |
| `interrogate-paths` | `"."` | space-separated paths for interrogate; scoped by `[tool.interrogate]` excludes |
| `migrations-path` | `"alembic/versions"` | migrations directory the `migrations` gate watches |
| `gitleaks-version` | `"8.30.1"` | gitleaks release to install |
| `djlint-spec` | `"djlint>=1.36,<2"` | pip spec for djlint — match your pyproject pin |
| `djlint-paths` | `"templates/"` | space-separated template paths for djlint; profile/ignores from `[tool.djlint]` |
| `import-linter-spec` | `"import-linter>=2,<3"` | pip spec for import-linter — match your pyproject pin |
| `hadolint-version` | `"2.14.0"` | hadolint release to install |
| `hadolint-dockerfiles` | `"Dockerfile"` | space-separated Dockerfile paths to lint |
| `npm-audit-level` | `"high"` | severity at which npm audit fails the `js-deps` gate |
| `diff-cover-fail-under` | `"90"` | Minimum % coverage on changed lines |
| `free-disk-space` | `false` | Reclaim runner disk first (heavy ML dependency trees) |
| `enable-<gate>` | `true` | Per-gate opt-out (see above); new gates ship opt-in in a MINOR, then default-on in the next MAJOR |

### Files in your repo

| File | Needed for | Purpose |
|---|---|---|
| `pyproject.toml` with `[tool.bandit]` | `sast` | scan scope/excludes (plus your mypy/ruff config as usual) |
| `pyproject.toml` with `[tool.interrogate]` | `docstrings` | coverage threshold (`fail-under`) + excludes |
| `pyproject.toml` with `[tool.djlint]` | `templates` | djlint profile (e.g. `jinja`) + rule ignores |
| `pyproject.toml` with `[tool.importlinter]` | `import-linter` | your import contracts (root package(s) + layers/forbidden/independence) ([reference](example/pyproject.toml)) |
| `.colormath/audit.conf` | `deps` | poetry groups that ship + CVE allowlist ([reference](example/.colormath/audit.conf)) |
| npm scripts `test`, `jslint`, `styles`, `a11y` | the JS gates | see [example/package.json](example/package.json) |
| `eslint.config.js` + vendored `eslint.config.colormath.mjs` | `jslint` | thin caller of the shared eslint base ([reference](example/eslint.config.js)); devDeps `eslint`, `@eslint/js`, `globals` |
| `Dockerfile` | `dockerfile` | linted by hadolint ([reference](example/Dockerfile)) |
| `AGENTS.md` + vendored `AGENTS.colormath.md` | agents | app-specific facts locally, shared colormath conventions imported ([reference](example/AGENTS.md)) |
| `.colormath/ci.env` | optional | non-secret env sourced before pytest in CI |
| `.colormath/ci-extra-install.sh` | optional | extra install steps after `poetry install` (must be executable) |
| `.gitleaks.toml` | optional | gitleaks false-positive allowlist, used when present |

Once the checks are green, register each gate's job name as a required status
check in your branch protection (they appear as `gates / Ruff (format + lint)`
and so on) — and **remove the required contexts left over from your
pre-colormath workflow**. Old names never report under the suite, so each one
pins every PR at "Expected — waiting for status" and blocks merging.

## Optional: AI review

[review.yml](.github/workflows/review.yml) is a second reusable workflow —
entirely opt-in, adopted per project by adding a caller (skip the caller and
nothing changes). It runs one Claude agent on every non-draft PR
(re-runnable by commenting `@claude`):

- **review** — the "Thermonuclear Review": a deliberately adversarial audit of
  the diff across correctness, security, maintainability, and DevEx, posted as
  a tracking comment (marker line `## Thermonuclear Review`) with inline
  comments on the relevant lines.

**QA is not here.** A second `test-plan` agent used to post a `## Test Plan`
comment on every PR; it has been removed. The QA plan belongs to the ticket in
Abacus, where the `refine-ticket` skill writes it and the `ship` skill
executes it against a running stack — the thing CI cannot do. See
[Where QA lives](#where-qa-lives).

### Installing the review workflow

The agent runs via `anthropics/claude-code-action`, which needs more than
the caller file — do these once per repo, in order:

1. **Install the [Claude GitHub App](https://github.com/apps/claude)** on the
   repo (or org). The action exchanges OIDC (`id-token: write`) for an app
   token and posts its comments as `claude[bot]` — without the app installed,
   the agent cannot authenticate to GitHub and the job fails at startup.
2. **Add the API key secret**:
   `gh secret set ANTHROPIC_API_KEY --repo <owner>/<repo>`
   (an Anthropic API key with access to the model you configure).
3. **Add the caller workflow** below, pinned to an exact tag.
4. Optionally set `review-focus` to point the reviewer at your project's
   sensitive surfaces — without it the review is generic.

```yaml
name: claude-review

on:
  pull_request:
    types: [opened, reopened, ready_for_review]
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]

jobs:
  review:
    uses: ColorMath/ci/.github/workflows/review.yml@vX.Y.Z  # latest: /releases/latest
    permissions:
      contents: read
      pull-requests: write
      issues: write
      id-token: write
    secrets:
      anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    with:
      review-focus: "Pay attention to <project-specific hot spots>."
```

Inputs: `review-focus` (extra project-specific emphasis for the reviewer), an
`enable-review` toggle, `skip-paths`, and model/effort controls. Requires an
`ANTHROPIC_API_KEY` repo secret.

| Input | Default | Purpose |
|---|---|---|
| `model` | `"claude-sonnet-4-6"` | Fallback when `review-model` is unset |
| `review-model` | `""` → `model` | Model for the review agent |
| `review-effort` | `"low"` | `--effort` for the review agent |
| `skip-paths` | `**/*.md`, `**/*.lock`, `**/package-lock.json`, `LICENSE` | PRs whose files *all* match are not reviewed |

The reviewer stays on Sonnet, where adversarial depth actually buys findings,
but at `low` effort. Measured over 30 intendent reviews, cost tracks turn count
(r=0.86) more closely than diff size (r=0.75), and effort is the input that most
directly buys turns — so it is the first dial to turn and the first to turn back
if the reviewer starts missing things. **`effort` is rejected by Haiku 4.5 and
Sonnet 4.5**, so if you move `review-model` down, clear `review-effort` in the
same edit or the request fails.

`skip-paths` is deliberately conservative, and the rule is **all or nothing**: a
PR is skipped only when *every* changed file matches. A PR touching code and
docs is reviewed in full, docs included — so the skip fires on a typo fix or a
lockfile bump, never on a change that happens to include a README. A `triage`
job makes that call on a bare runner before any model is invoked, so a skipped
review costs Actions seconds rather than the ~$0.68 a review averages, and its
step summary lists exactly which files it judged. Set `skip-paths: ""` to review
everything; extend it if your repo generates other unreviewable files.

If your repo's *product* is markdown — a docs site, a prompt library — the
`**/*.md` default is wrong for you. Override it.

The `issue_comment` / `pull_request_review_comment` triggers are what enable
`@claude` re-runs, but they come with noise: GitHub can't filter comment
events by body at the trigger level, so **every** PR comment — including the
review's own bot comment — creates a run that immediately skips. If you
prefer a quiet Actions tab, keep only the `pull_request` trigger and re-run
reviews from the Actions UI (or flip the PR draft → ready).

### Where QA lives

Not in CI. A QA plan is a set of claims about a *running* system — this page
renders for that role, this endpoint 403s for the other one — and a workflow
cannot bring the app up, log in as three identities and watch what happens. The
`test-plan` agent that used to run here could therefore only write the plan,
never execute it, which put the plan on the one surface least able to act on it
and billed a second agent per PR to get it there.

So QA belongs to the **ticket**:

| Stage | Skill | What it does |
|---|---|---|
| Grooming | `refine-ticket` | Writes the ticket's `qa_plan` field alongside its implementation plan |
| Building | `implement-ticket` | Executes that plan against a running stack as it builds |
| Shipping | `ship` | Re-executes it on the PR; **writes one if the ticket has none** |

`ship` fills an empty `qa_plan` and marks it as ship-authored, but never edits a
groomed one — amendments go on as ticket comments, so the field stays the record
of what was intended and the comments record what actually happened. A PR with
no ticket still gets QA'd; the plan just lives in the PR.

## Optional: agent plugin

The `plugin/` package exposes one canonical Agent Skills tree to Claude Code,
Codex, and other hosts implementing the
[Agent Skills standard](https://agentskills.io/specification). The `colormath`
plugin ships seven skills for working in consumer repos:
**`ship`** takes the current branch through the whole PR pipeline
(open the PR, watch the gates, wait for the Thermonuclear Review, execute the
ticket's **QA plan** against the running stack — writing one when the ticket has
none — and post its results, fix every finding it can — blockers included) and
ends at a gated final review that
**auto-merges** when the PR is genuinely clean or holds and explains why;
**`qa`** QAs a focus area against the running stack and hands the
fixes to `ship`; **`bugfix`** turns a *specific* bug report into a
merged fix — establishing the facts the report omitted, reproducing the defect
before touching code, fixing at the layer the invariant belongs to, remediating
data the bug already corrupted, then handing off to `ship`; and
**`refine-ticket`** grooms a ticket until it can be worked —
investigating the code *before* it asks anything, so its questions are few and
concrete, then writing back a standalone description, an implementation plan
whose every step names a real file, and a QA plan someone could execute; and
**`refine-initiative`** does the layer above for an initiative —
reading its feature definitions, investigating the architecture and decision
records they land in, interviewing until the picture is complete, then rewriting
the initiative and every feature with the background implementation needs, while
stopping short of code-level plans and never starting the build; and
**`plan-initiative`** closes the loop between the two — running
`refine-ticket` over every ticket in an initiative, in build order, injecting
each ticket's place in the sequence and what the earlier plans decided, so the
seams line up instead of seven independent groomings contradicting each other;
and **`implement-ticket`** takes a groomed ticket the rest of the way
— checking its plan still matches the code before touching anything, building at
the layer the plan names, executing the ticket's QA plan against the running
stack, then handing off to `ship`. Each skill's behavior, prerequisites, and
contract dependencies are documented in [plugin/README.md](plugin/README.md).

`refine-ticket`, `refine-initiative`, `plan-initiative` and
`implement-ticket` need the [Abacus](https://github.com/ColorMath/abacus) MCP
server connected — the plugin's one tracker dependency.

### Claude Code installation and invocation

Claude Code uses [`plugin/.claude-plugin/plugin.json`](plugin/.claude-plugin/plugin.json)
and namespaces plugin skills. Install from this repository's Claude marketplace:

```text
/plugin marketplace add ColorMath/ci
/plugin install colormath@colormath
/colormath:bugfix CM-00012
```

To offer it to everyone who opens a consumer repo, configure
`.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "colormath": {
      "source": { "source": "github", "repo": "ColorMath/ci" }
    }
  },
  "enabledPlugins": {
    "colormath@colormath": true
  }
}
```

### Codex installation and invocation

Codex uses [`plugin/.codex-plugin/plugin.json`](plugin/.codex-plugin/plugin.json).
After a local or team Codex marketplace points at `plugin/`, install it with the
marketplace's configured name and mention the skill with Codex's native `$`
syntax:

```text
codex plugin add colormath@<marketplace-name>
$colormath:bugfix Fix CM-00012
```

### Generic Agent Skills installation and invocation

For another Agent Skills-compatible host, install each directory under
`plugin/skills/` into that host's documented skills directory. Invoke dependent
workflows through the host's native mechanism, or ask for them by logical name:

```text
cp -R plugin/skills/* <host-skills-directory>/
Use the bugfix skill to fix CM-00012.
```

The canonical skills require the capabilities named in each `compatibility`
field. Hosts may expose different tool names; the workflows intentionally refer
to shell, filesystem, structured questions, skill invocation, browser access,
and Abacus MCP tools by capability rather than rendered host symbol.

## Running the gates locally

Three files are vendored into every consumer at the pinned tag:
[Makefile.colormath](Makefile.colormath) (a local mirror of every gate, so
all consumers share the same `make` endpoints),
[eslint.config.colormath.mjs](eslint.config.colormath.mjs) (the shared eslint
base — your `eslint.config.js` stays a thin caller; see its header for the
factory options and escape hatches), and
[AGENTS.colormath.md](AGENTS.colormath.md) (the shared agent conventions — see
[Agent docs](#agent-docs) below). Vendor them once:

```sh
# REF is the release you are pinning to — see github.com/ColorMath/ci/releases/latest
REF=vX.Y.Z
curl -fsSLO "https://raw.githubusercontent.com/ColorMath/ci/$REF/Makefile.colormath"
curl -fsSLO "https://raw.githubusercontent.com/ColorMath/ci/$REF/eslint.config.colormath.mjs"
curl -fsSLO "https://raw.githubusercontent.com/ColorMath/ci/$REF/AGENTS.colormath.md"
```

Thereafter `make colormath-update REF=vX.Y.Z` refreshes all three in one step.

then include the Makefile from yours, providing the one target it expects
from you (`test`) and setting knobs before the include if your project
differs:

```make
# COLORMATH_DIFF_COVER_BASE = origin/master   # example override
COLORMATH_PREFLIGHT_SKIP = templates          # mirror your enable-*: false flags
include Makefile.colormath

test: ## your mirror of the tests gate
	poetry run pytest tests/ && npm test
```

Now every gate has a same-named `make` mirror (`make jslint`, `make audit`,
`make dockerfile`, …), and `make preflight` runs the full suite minus
`COLORMATH_PREFLIGHT_SKIP` — keep that list in lockstep with the gates your
caller disables. The `audit` and `coverage-diff` targets fetch their gate
scripts from this repo at the file's own stamped tag, so local runs and CI
share one implementation. On upgrades, `make colormath-update REF=vX.Y.Z`
refreshes all three vendored files — keep them in lockstep with your
`gates.yml` pin, and review the diff like any other dependency bump.

## Agent docs

Coding agents need the same facts the gate table above gives a human: which
gates exist, when to run preflight, how a branch ships, what never to touch.
Written per-repo, those facts drift — four apps end up with four descriptions
of one gate suite, and the stale ones are indistinguishable from the current
ones.

[AGENTS.colormath.md](AGENTS.colormath.md) is that content, vendored like the
other two files and refreshed by the same `make colormath-update`. Your own
`AGENTS.md` keeps only what is true of your app — domain, commands, ports,
architecture, local conventions — and imports the shared half:

```markdown
# YourApp

One paragraph on what this app is and what it's built from.

Shared colormath conventions (CI gates, shipping, guardrails): @AGENTS.colormath.md

## Commands
…
```

The import line is written as a sentence on purpose: `@path` is Claude Code
syntax, and an agent that doesn't resolve it still reads a usable pointer.

Two things deliberately stay in *your* `AGENTS.md`, because the shared copy
cannot know them: which gates your caller disables (that lives in `gates.yml`
and `COLORMATH_PREFLIGHT_SKIP`, which are the authority), and where your design
tokens live. [example/AGENTS.md](example/AGENTS.md) shows the wiring.

## Versioning and upgrades

One SemVer tag stream, and consumers pin **exact tags only** (a specific
`@vX.Y.Z`, never a floating major tag): an upgrade should arrive as a
reviewable PR whose diff and changelog explain themselves — not as a surprise
inside an unrelated one. Every tag has a
[GitHub Release](https://github.com/ColorMath/ci/releases) carrying that
version's changelog section, so
[releases/latest](https://github.com/ColorMath/ci/releases/latest) is the
authoritative answer to "what should I pin to?"

The snippets above deliberately say `vX.Y.Z` rather than a real version. Pins
written into documentation rot silently — these had been sitting three
releases stale — so there is nothing here to keep up to date.

The rule for MAJOR: *if a consumer's CI can go from green to red without the
consumer editing anything, it's MAJOR.* New gates ship disabled-by-default in
a MINOR and are promoted to default-on in the next MAJOR. Details in
[LIFECYCLE.md](LIFECYCLE.md); release history in [CHANGELOG.md](CHANGELOG.md).
While on `0.x`, breaking changes may land in any release.

## What's in this repo

```
.github/workflows/gates.yml    # the reusable gate suite (workflow_call)
.github/workflows/review.yml   # optional reusable AI review workflow
.github/workflows/ci.yml       # self-test: runs the suite against example/
.github/actions/               # setup-python-poetry, setup-node, gate-summary
.claude-plugin/                # plugin marketplace manifest
plugin/                        # shared Agent Skills plugin (Claude, Codex, generic hosts)
Makefile.colormath             # shared local gate targets — vendored by consumers
eslint.config.colormath.mjs    # shared eslint base — vendored by consumers
AGENTS.colormath.md            # shared agent conventions — vendored by consumers
scripts/                       # gate scripts, fetched by the workflow at its own ref
release/                       # release tooling — stamp, verify, cut (not shipped)
example/                       # minimal compliant consumer + contract reference
docs/                          # adoption notes for the maintainer's own products
```

Planned next, on the same tag stream and exact-pin rule: a Copier template for
the in-repo files this stack shares (Dockerfile, Makefile, compose), and
Terraform modules for the Cloud Run deployment shape.

## Design principle

colormath ships **no runtime application code** — infrastructure only. The
10-second rule for what belongs here: would a sibling project copy this file
unmodified except for names, ports, and IDs? Then it belongs in colormath.
Does it mention a specific domain, or need more than ~3 template variables to
fit every project? Then it's a product decision wearing a costume; keep it in
your repo.

This repo is public so consumers under any GitHub owner can use every channel
without auth friction. Never commit real project IDs or secrets — the gitleaks
gate runs on colormath itself, and example values must stay obviously fake.

## License

[MIT](LICENSE)
