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
    uses: ColorMath/ci/.github/workflows/gates.yml@v2.0.0
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
    uses: ColorMath/ci/.github/workflows/gates.yml@v2.0.0
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
| `.colormath/ci.env` | optional | non-secret env sourced before pytest in CI |
| `.colormath/ci-extra-install.sh` | optional | extra install steps after `poetry install` (must be executable) |
| `.gitleaks.toml` | optional | gitleaks false-positive allowlist, used when present |

Once the checks are green, register each gate's job name as a required status
check in your branch protection (they appear as `gates / Ruff (format + lint)`
and so on) — and **remove the required contexts left over from your
pre-colormath workflow**. Old names never report under the suite, so each one
pins every PR at "Expected — waiting for status" and blocks merging.

## Optional: AI review + test plan

[review.yml](.github/workflows/review.yml) is a second reusable workflow —
entirely opt-in, adopted per project by adding a caller (skip the caller and
nothing changes). It runs two Claude agents in parallel on every non-draft PR
(re-runnable by commenting `@claude`):

- **review** — the "Thermonuclear Review": a deliberately adversarial audit of
  the diff across correctness, security, maintainability, and DevEx, posted as
  a tracking comment (marker line `## Thermonuclear Review`) with inline
  comments on the relevant lines.
- **test-plan** — classifies the diff (UI vs API surface) and posts a
  `## Test Plan` comment with concrete QA checklists, exposing a
  machine-readable verdict (`qa_depth`, `requires_ui_qa`, `requires_api_qa`)
  as workflow outputs for downstream QA jobs to gate on.

### Installing the review suite

Both agents run via `anthropics/claude-code-action`, which needs more than
the caller file — do these once per repo, in order:

1. **Install the [Claude GitHub App](https://github.com/apps/claude)** on the
   repo (or org). The action exchanges OIDC (`id-token: write`) for an app
   token and posts its comments as `claude[bot]` — without the app installed,
   the agents cannot authenticate to GitHub and the jobs fail at startup.
2. **Add the API key secret**:
   `gh secret set ANTHROPIC_API_KEY --repo <owner>/<repo>`
   (an Anthropic API key with access to the model you configure; both agents
   share it).
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
    uses: ColorMath/ci/.github/workflows/review.yml@v2.0.0
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

Inputs: `review-focus` (extra project-specific emphasis for the reviewer),
`enable-review` / `enable-test-plan` toggles, and per-agent model and effort
controls. Requires an `ANTHROPIC_API_KEY` repo secret.

| Input | Default | Purpose |
|---|---|---|
| `model` | `"claude-sonnet-4-6"` | Fallback for whichever agent has no explicit model |
| `review-model` | `""` → `model` | Model for the review agent |
| `test-plan-model` | `"claude-haiku-4-5"` | Model for the test-plan agent |
| `review-effort` | `"medium"` | `--effort` for the review agent |
| `test-plan-effort` | `""` (no flag) | `--effort` for the test-plan agent |

The two agents are priced very differently in practice — on a representative
PR the reviewer cost $1.00 over 18 turns and the test-plan agent $0.53 over
14. So the defaults put the test-plan agent on Haiku (read-only analysis
producing a checklist — well inside its range, at a third of Sonnet's price)
and drop the reviewer to `medium` effort, while leaving the reviewer itself on
Sonnet, where adversarial depth actually buys findings.

Two sharp edges. **`effort` is rejected by Haiku 4.5 and Sonnet 4.5**, so
setting `test-plan-effort` while `test-plan-model` is on its Haiku default
will fail the request — move that model to a 4.6+ model first. And because
`test-plan-model` has a non-empty default, setting `model:` alone no longer
reaches both agents; set `test-plan-model:` too if you want one model
everywhere.

The `issue_comment` / `pull_request_review_comment` triggers are what enable
`@claude` re-runs, but they come with noise: GitHub can't filter comment
events by body at the trigger level, so **every** PR comment — including the
review's own two bot comments — creates a run that immediately skips. If you
prefer a quiet Actions tab, keep only the `pull_request` trigger and re-run
reviews from the Actions UI (or flip the PR draft → ready).

## Optional: Claude Code plugin

This repo is also a [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces).
The `colormath` plugin ships skills for working in consumer repos:
**`/colormath:ship`** takes the current branch through the whole PR pipeline
(open the PR, watch the gates, wait for the Thermonuclear Review, execute the
generated **test plan** against the running stack and post its results, fix
every finding it can — blockers included) and ends at a gated final review that
**auto-merges** when the PR is genuinely clean or holds and explains why;
**`/colormath:qa`** QAs a focus area against the running stack and hands the
fixes to `ship`; **`/colormath:bugfix`** turns a *specific* bug report into a
merged fix — establishing the facts the report omitted, reproducing the defect
before touching code, fixing at the layer the invariant belongs to, remediating
data the bug already corrupted, then handing off to `ship`; and
**`/colormath:refine-ticket`** grooms a ticket until it can be worked —
investigating the code *before* it asks anything, so its questions are few and
concrete, then writing back a standalone description, an implementation plan
whose every step names a real file, and a QA plan someone could execute; and
**`/colormath:refine-initiative`** does the layer above for an initiative —
reading its feature definitions, investigating the architecture and decision
records they land in, interviewing until the picture is complete, then rewriting
the initiative and every feature with the background implementation needs, while
stopping short of code-level plans and never starting the build; and
**`/colormath:plan-initiative`** closes the loop between the two — running
`refine-ticket` over every ticket in an initiative, in build order, injecting
each ticket's place in the sequence and what the earlier plans decided, so the
seams line up instead of seven independent groomings contradicting each other;
and **`/colormath:implement-ticket`** takes a groomed ticket the rest of the way
— checking its plan still matches the code before touching anything, building at
the layer the plan names, executing the ticket's QA plan against the running
stack, then handing off to `ship`. Each skill's behavior, prerequisites, and
contract dependencies are documented in [plugin/README.md](plugin/README.md).

`refine-ticket`, `refine-initiative`, `plan-initiative` and
`implement-ticket` need the [Abacus](https://github.com/ColorMath/abacus) MCP
server connected — the plugin's one tracker dependency.

Install manually:

```
/plugin marketplace add ColorMath/ci
/plugin install colormath@colormath
```

or have a consumer repo offer it to everyone who opens it, via
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

## Running the gates locally

Two files are vendored into every consumer at the pinned tag:
[Makefile.colormath](Makefile.colormath) (a local mirror of every gate, so
all consumers share the same `make` endpoints) and
[eslint.config.colormath.mjs](eslint.config.colormath.mjs) (the shared eslint
base — your `eslint.config.js` stays a thin caller; see its header for the
factory options and escape hatches). Vendor them once:

```sh
curl -fsSLO https://raw.githubusercontent.com/ColorMath/ci/v2.0.0/Makefile.colormath
curl -fsSLO https://raw.githubusercontent.com/ColorMath/ci/v2.0.0/eslint.config.colormath.mjs
```

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
refreshes both vendored files — keep them in lockstep with your `gates.yml`
pin, and review the diff like any other dependency bump.

## Versioning and upgrades

One SemVer tag stream, and consumers pin **exact tags only** (`@v2.0.0`, never
a floating major tag): an upgrade should arrive as a reviewable PR whose diff
and changelog explain themselves — not as a surprise inside an unrelated one.

The rule for MAJOR: *if a consumer's CI can go from green to red without the
consumer editing anything, it's MAJOR.* New gates ship disabled-by-default in
a MINOR and are promoted to default-on in the next MAJOR. Details in
[LIFECYCLE.md](LIFECYCLE.md); release history in [CHANGELOG.md](CHANGELOG.md).
While on `0.x`, breaking changes may land in any release.

## What's in this repo

```
.github/workflows/gates.yml    # the reusable gate suite (workflow_call)
.github/workflows/review.yml   # optional reusable AI review + test-plan suite
.github/workflows/ci.yml       # self-test: runs the suite against example/
.github/actions/               # setup-python-poetry, setup-node, gate-summary
.claude-plugin/                # plugin marketplace manifest
plugin/                        # the colormath Claude Code plugin (skills)
Makefile.colormath             # shared local gate targets — vendored by consumers
eslint.config.colormath.mjs    # shared eslint base — vendored by consumers
scripts/                       # gate scripts, fetched by the workflow at its own ref
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
