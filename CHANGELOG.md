# Changelog

All notable changes to colormath. Versioning per [LIFECYCLE.md](LIFECYCLE.md):
one SemVer stream, exact-tag pins, MAJOR = anything that can turn a consumer's
green CI red without the consumer editing anything. While on `0.x`, breaking
changes may land in any release.

Changes land under `## Unreleased`; `release/cut.sh` renames that heading to the
version being cut and opens a fresh one. The date on a section is the date the
release was cut, and every section from `v3.1.0` on is also the body of that
version's [GitHub Release](https://github.com/ColorMath/ci/releases).

## Unreleased

## v4.1.0 — 2026-08-19

MINOR. Behaviour added to an existing plugin skill; no gate becomes stricter and
nothing a consumer runs can turn red without them editing anything.

### Added

- **`ship` links its PR to the ticket, and holds if it did not.** Abacus has had
  `link_pull_request` since CM-00019 and nothing ever called it: ship opened the
  PR knowing exactly which ticket it came from, captured the number for its own
  later steps, and threw the connection away. That ticket's own description
  predicted this would happen, and it did.

  Two changes, deliberately different in kind. Step 1 links the PR immediately
  after `gh pr create` — that is the instruction. Step 7 gains a fourth merge
  gate that refuses to auto-merge a PR whose ticket does not name **this** PR's
  number — that is what makes "always" mean always, because an instruction alone
  is what an agent skips when the run is long and the gates are red.

  `bugfix` and `implement-ticket` both hand off to ship rather than opening PRs
  themselves, so all three inherit it.

  Three edges are settled in the skill rather than left to judgement: a duplicate
  link is refused and reads as **success** on a re-run; a repository that is not
  connected to the board is a **hold**, never a guess at which repository was
  meant; and a branch with no ticket has nothing to link and must not become a
  spurious hold.

  `allowed-tools` gains `mcp__abacus__get_board` and
  `mcp__abacus__link_pull_request`. Without both the calls are simply
  unavailable, which is a prerequisite rather than a detail.

  **Requires an Abacus deployed with ColorMath/abacus#49.** That PR is what makes
  the two reads this depends on exist: `get_board` returns the board's connected
  repositories (so a repository id can be discovered at all — its schema pointed
  there and the field did not exist), and `get_ticket` returns the ticket's
  linked pull requests (so the merge gate has something to read on a re-run).
  Landing this first would give ship an instruction it cannot carry out.

## v4.0.0 — 2026-08-12

MAJOR. The review workflow loses a job, three inputs and three outputs. A
consumer that passes any of the removed inputs goes red on its next run without
editing anything, which is the test in [LIFECYCLE.md](LIFECYCLE.md).

### Fixed

- **`refine-initiative`'s frontmatter was not valid YAML.** Its `description`
  contained an unquoted `plans: those belong…`, and a bare `: ` inside a plain
  scalar makes the parser read a nested mapping where a string was meant — so
  the whole block failed to load. Rewritten with an em-dash, matching how every
  other skill in the plugin punctuates the same construction. The wording is
  otherwise untouched.

  Worth knowing because the symptom is silent: the skill was shipped in v3.1.0
  and nothing in CI parses skill frontmatter, so a description that never loads
  looks exactly like one that loads fine until a client tries to read it. All
  seven skills now parse, and their descriptions round-trip complete.

### Removed

- **The `test-plan` agent, and the QA comment it posted on every PR.** The
  review workflow now runs one agent — the Thermonuclear Review — instead of
  two. Gone with it: the `## Test Plan` comment and its
  `<!-- colormath-test-plan -->` / `<!-- testplan … -->` verdict markers, the
  `enable-test-plan` / `test-plan-model` / `test-plan-effort` inputs, the
  `qa_depth` / `requires_ui_qa` / `requires_api_qa` workflow outputs, and the
  placeholder `api-qa` / `ui-qa` jobs that gated on them.

  A QA plan is a set of claims about a *running* system — this page renders for
  that role, this endpoint 403s for the other one. A GitHub workflow cannot
  bring the app up, log in as three identities and watch what happens, so the
  test-plan agent could only ever **write** the plan. That put the plan on the
  one surface least able to act on it, and billed a second agent per PR to get
  it there. The plan now lives on the ticket, where grooming already writes one
  and where `ship` can execute it.

  The `model` input keeps its name and default but now feeds only the reviewer;
  with `test-plan-model` gone, setting `model:` alone once again configures
  everything the workflow runs.

### Changed

- **The review no longer runs on PRs with no code in them, and thinks less hard
  by default.** Two cost changes, measured rather than guessed. Across 30
  intendent reviews on v3.1.0 the reviewer averaged **$0.68** (median $0.63,
  range $0.30–$1.82) over 21 turns; cost correlates with turn count at r=0.86
  and with diff size at only r=0.75 — a 145-line PR burned 47 turns and $1.12
  while a 1,711-line PR cost $0.97 in 19.

  So: **`review-effort` drops from `medium` to `low`**, effort being the input
  that most directly buys turns. The previous step, default-`high` → `medium` in
  v3.0.0, took the reviewer from $1.00 to $0.68; this one is the same dial one
  notch further. It is the first thing to turn back if a repo finds the reviewer
  missing things, and `review-effort: medium` in the caller restores the old
  behavior exactly.

  And a **`triage` job** now decides whether the diff is worth reviewing at all.
  It lists the PR's files over one REST call on a bare runner — no model — and
  skips the review when **every** file matches the new `skip-paths` input
  (default: `**/*.md`, `**/*.lock`, `**/package-lock.json`, `LICENSE`). The
  all-or-nothing rule is the point: a PR touching code *and* docs is reviewed in
  full, docs included, so the skip fires on a typo fix or a lockfile bump and
  never on a real change that happens to carry a README. `skip-paths: ""`
  reviews everything.

  `review / review` therefore now shows as `SKIPPED` on those PRs, which is a
  new state for anything reading that check. `ship` learned to tell it apart
  from a review that errored before posting — the first is "there was nothing to
  audit" and satisfies its merge gate, the second still holds the merge — and
  cross-checks `review / triage`'s step summary so a misconfigured `skip-paths`
  surfaces as a question rather than a silent merge.

  A repo whose *product* is markdown wants a different default; override
  `skip-paths` there.

- **`ship` takes its QA plan from the ticket, and writes one when there isn't
  one.** Step 4 was "wait for the test-plan agent, then execute what it posted."
  It is now: resolve the ticket from the branch, PR title/body and commits; read
  its `qa_plan` over MCP; execute that against the running stack.

  What happens when the plan is missing or wrong is the substance of this
  change. An **empty** `qa_plan` gets filled — ship drafts one from the diff and
  writes it to the field, opening it with a line naming its provenance
  (`_Authored by /colormath:ship while shipping PR #<n> — not groomed._`) so a
  later reader never mistakes it for something that was reviewed. A **groomed**
  `qa_plan` is never edited: where it has gone stale, the amendment goes on as a
  ticket comment and the amended version is what runs. The field stays the
  record of what was intended; comments are the record of what happened — the
  same split `implement-ticket` already keeps. A PR with **no** ticket still
  gets QA'd; that plan just lives in the PR, and ship does not invent a ticket
  to hold it.

  Results are posted twice: a `## QA Results` comment on the PR (renamed from
  `## Test Plan · Results`), mirrored onto the ticket, because a plan whose
  results only ever existed on a PR is one nobody can audit later.

  Two knock-on corrections. The merge decision's third gate used to end "No
  review workflow at all → no test plan → this gate fails"; QA no longer depends
  on the review workflow, so a missing ticket is explicitly *not* an excuse for
  skipping it. And the first gate now says plainly that a missing or errored
  review fails it — a clean QA run does not substitute for a review that never
  happened.

  `allowed-tools` gains `mcp__abacus__get_ticket`, `update_ticket`,
  `add_comment`, `list_boards` and `list_tickets`. With no abacus MCP server
  configured the step still runs: ship drafts the plan in the PR and says no
  ticket backed it.

- **`ship`'s "one review per run" rule keeps its teeth, on a new argument.** The
  rule was justified partly by the test-plan agent — a re-review spawned a fresh
  plan and a fresh QA round. That agent is gone; the loop is not. Re-reviewing a
  diff you have already responded to still yields findings that look substantive
  enough to justify another round of fixes, QA and review, with no exit
  condition. The plugin README also described step 5 as "re-triggering the
  review with `@claude` once when fixes are substantive", which contradicted the
  skill it documents; that is corrected.

- **`bugfix` now takes a ticket key as well as a pasted report.**
  `/colormath:bugfix CM-00012` reads the ticket over MCP — description, type,
  every comment, and the plans if it was groomed — instead of needing the report
  pasted in. Prose, a stack trace and a path to a report file all behave exactly
  as before; the skill now branches on which of the three shapes it was handed.

  The gap this closes is that a bug usually **is** a ticket by the time somebody
  fixes it. `refine-ticket`, `implement-ticket`, `refine-initiative` and
  `plan-initiative` all take a key; `bugfix` was the odd one out, so the only
  way to hand it a filed bug was to copy the description out of the tracker —
  which silently drops the comment thread, where a filed bug's actual
  reproduction usually ends up.

  Reading the thread is the point, not a side effect: the skill is told to read
  **every comment**, because the environment, the repro somebody finally landed
  on, and the "it also happens when…" are typically there rather than in the
  description. What it must not do is treat a numbered ticket as more
  authoritative than a pasted paragraph — step 1 ("find what's missing") applies
  unchanged either way.

  It also closes the loop: when a run started from a ticket, the skill now
  `add_comment`s the outcome — PR link, merged or held, the cause, and what it
  deliberately left alone — matching what `implement-ticket` already does. It
  leaves the ticket's own fields and lane alone; the description is what was
  reported, the comment is what happened, and whether a bug is done is the
  filer's call.

  `allowed-tools` gains `mcp__abacus__get_ticket`, `list_boards`, `list_tickets`
  and `add_comment` — the same read set `refine-ticket` carries, plus the
  comment write. A consumer with no abacus MCP server configured is unaffected:
  the pasted-report path never touches those tools.

  Downstream, this makes `/colormath:bugfix <key>` a command a tracker can print
  next to a bug and have somebody run as-is, which it could not before.

### Upgrade notes

Paste into Claude Code in each consumer repo:

> Bump the colormath pins to `vX.Y.Z`: update the `uses:` refs in
> `.github/workflows/gates.yml` and the review caller (`review.yml` or
> `review.yaml`), set `COLORMATH_REF` in `Makefile.colormath` to match, and run
> `make colormath-update REF=vX.Y.Z` to refresh the vendored files. Then open
> the review caller and delete any `test-plan-model`, `test-plan-effort` or
> `enable-test-plan` input under `with:` — those inputs no longer exist and
> passing one fails the workflow at startup. If any job in this repo has
> `needs:` on the review job and reads `qa_depth`, `requires_ui_qa` or
> `requires_api_qa` from its outputs, delete that job — those outputs are gone.
> The review also now defaults to `review-effort: low` and skips PRs whose files
> all match `skip-paths`; if this repo's product is markdown, set `skip-paths`
> to something narrower in the caller. Finally run `make preflight`.

Most repos need only the pin bump: neither intendent nor talas passed any of the
removed inputs, and the placeholder `api-qa` / `ui-qa` jobs lived inside
colormath rather than in consumers. The `## Test Plan` comments already on open
PRs are inert — nothing reads them any more; leave them or delete them.

If you keyed anything of your own on the `## Test Plan` marker or the
`<!-- colormath-test-plan -->` HTML comment, it will now find nothing. The
equivalent is `## QA Results`, posted by `/colormath:ship` rather than by CI —
so it lands when the branch is shipped, not when the PR opens.

## v3.1.0 — 2026-08-04

MINOR. Three new plugin skills and a new vendored file are additive per
[LIFECYCLE.md](LIFECYCLE.md), and the skill rename below — while a real break
for anyone with the old command in their fingers — cannot turn a consumer's CI
red, which is the test that makes a release MAJOR.

### Fixed

- **`make coverage-diff` did not source `.colormath/ci.env`**
  (`Makefile.colormath`). CI's `diff-coverage` gate sources it before running
  pytest; the local mirror of that gate did not. So a consumer whose app needs
  test configuration to import at all — a session secret, a provider key —
  got a passing gate in CI and a collection error locally, from the same
  commit. `make preflight` is only useful if it runs what CI runs.

  Found while bumping intendent to v3.0.0: `make test` had been fixed to
  mirror CI, and `coverage-diff` was the one remaining target still running
  pytest with the wrong environment. The fix uses the same `if [ -f … ]; then
  set -a; . …; set +a; fi` form as the CI step, so the two are literally the
  same idiom.

  This closes the half colormath owns, and only that half. Whether the app
  *also* reads a local `.env` is the consumer's business: a `.env` holding
  container-only paths still leaks into host runs, and neutralizing that stays
  with the consumer. So a consumer workaround can shed its ci.env-sourcing
  half at this release, but not necessarily all of it.

- **The two stamped refs could drift, and had** (`Makefile.colormath`,
  `.github/workflows/ci.yml`, `LIFECYCLE.md`). `gates.yml`'s `colormath-ref`
  default is how CI fetches its gate scripts; `Makefile.colormath`'s
  `COLORMATH_REF` is how `make preflight` fetches the same ones. The release
  checklist stamped only the first, so `COLORMATH_REF` sat at `v2.0.0` while
  CI moved to `v3.0.0` — preflight fetching scripts from a tag three releases
  behind the workflow.

  Harmless so far purely by luck: `audit-deps.sh`, `migrations-sync.sh` and
  `diff-coverage.sh` are byte-identical between `v2.0.0` and `v3.0.0`. The
  first script change would have made local and CI disagree with no signal.

  The `refs-lockstep` job added here was the right instinct and the wrong
  check. It compared the two stamps to *each other* and never asked whether the
  ref resolved — so when this release was stamped `v3.1.0` before the tag
  existed, it passed while every consumer's `make preflight` would have 404'd
  on every gate script. See the release-machinery entry below, which replaces
  it and makes hand-stamping impossible in the first place.

- **Releases are now atomic** (`release/`, `.github/workflows/release.yml`,
  `.github/workflows/ci.yml`, `LIFECYCLE.md`). Releasing was a six-step
  checklist, and the steps came apart. An audit of all sixteen published tags
  found nine internally inconsistent: `v2.1.0` through `v2.4.0` each ship a
  `gates.yml` that fetches its gate scripts from `v2.0.0`, and `v3.0.0`'s
  `Makefile.colormath` points three releases back. This release was itself
  stamped into `main` and written up here without ever being tagged, leaving
  `main` advertising a ref that 404s.

  The root cause was stamping *forward*: a human wrote the next version into
  the tree days before the tag existed, and the window between the two closed
  only if they remembered. Stamps now move only in the release commit, which is
  tagged with the version it stamps in a single `git push --atomic` — git
  updates both refs or neither, so the window is gone rather than merely
  shortened. In steady state `main` is stamped at the last released tag and
  every ref in it resolves.

  `release/cut.sh` is the one gesture: it refuses to start unless the tree is
  clean, synced with `origin/main`, and green in CI; stamps; re-verifies;
  commits; creates an *annotated* tag (the history alternates between
  lightweight and annotated); pushes atomically; then publishes the GitHub
  Release from this file's section for that version. A rejected push rolls the
  local commit and tag back, and a failure after the push is resumable, because
  publishing is idempotent.

  `release/verify.sh` replaces `refs-lockstep` in CI and is a strict superset:
  it covers `plugin.json` — a stamp site nothing checked, and which had been
  missed twice — asks whether the stamped ref *resolves*, and requires
  `example/`'s vendored copies to stay byte-identical to the root ones.
  `--audit-all` produced the drift table above and stays advisory, because
  published tags are never rewritten.

- **Documentation no longer names a version** (`README.md`,
  `.github/workflows/gates.yml`, `.github/workflows/review.yml`). Nine
  copy-paste pins had rotted — the README told consumers to pin `@v2.0.0` and
  the two workflow usage-comments said `@v1.1.0` and `@v1.0.0`, while the repo
  was on `v3.1.0`. They now read `@vX.Y.Z` and point at
  `/releases/latest`, and `verify.sh` fails the PR if a concrete version
  reappears. Automating the stamping of prose would have worked; deleting the
  data was cheaper and cannot regress.

- **Every tag has a GitHub Release.** All sixteen were bare; the notes existed
  only here. `release/backfill-releases.sh` created them retroactively from
  this file, and `cut.sh` creates them going forward, so
  `/releases/latest` is now a real answer to "what should I pin to?"

### Changed

- **`/colormath:review-ticket` is now `/colormath:refine-ticket`**
  (`plugin/skills/refine-ticket/`). Same skill, same behavior, same contract
  surfaces — only the command name moves, so that the two grooming skills read
  as the pair they are: `refine-ticket` for a ticket, `refine-initiative` for
  the initiative above it. "Review" also collided with the *other* review in
  this plugin — the Thermonuclear Review that `ship` waits on — which is an
  adversarial audit of a diff, not grooming.

  **This breaks muscle memory and any docs that name the old command.**
  `/colormath:review-ticket` stops existing at this release; there is no alias.
  MINOR rather than MAJOR under [LIFECYCLE.md](LIFECYCLE.md)'s test, which is
  about a consumer's CI going red without them editing anything — a skill is
  invoked by a person, and no gate, workflow input or Makefile target moves
  here. Grep your consumer repos for `colormath:review-ticket` when you take
  this release; product copy that tells users to run it is the likely hit.

### Added

- **`AGENTS.colormath.md`** — a third vendored file, alongside
  `Makefile.colormath` and `eslint.config.colormath.mjs` and refreshed by the
  same `make colormath-update`. It carries the half of a consumer's agent docs
  that is identical in every colormath app: what being a colormath app means,
  the sixteen gates with their local `make` mirrors and how to pass each, the
  preflight rhythm, the `/colormath:ship` pipeline, the layering and
  design-token and docstring conventions, the ADR practice, and the guardrails
  (never hand-edit the vendored files, never push to the default branch, never
  touch `.env`, justify every CVE ignore).

  The problem it solves is drift, and the drift was already there. Surveying
  four consumers, the gate suite was documented four ways — sixteen gates, nine
  gates, nine gates, seven gates — and one repo's doc named two disabled gates
  that were not the two its `gates.yml` actually disables. Each copy was right
  when written, and nothing marks the ones that stopped being right.

  Consumers keep an `AGENTS.md` of their own and import this one from it
  (`@AGENTS.colormath.md`), so app-specific facts stay app-specific. Two things
  deliberately do *not* move here: which gates a consumer disables — that is
  `enable-<gate>: false` plus `COLORMATH_PREFLIGHT_SKIP`, and prose about them
  is exactly what went stale — and where a consumer's design tokens live. The
  shared file states the rule and points at the local file for the value.

  Additive: nothing reads it in CI and no gate, input or target changes. A
  consumer that never vendors it is unaffected; one that does gets the file on
  its next `colormath-update`, and wires up the import in that same PR.
  `example/` carries the wiring as the reference.

- **`/colormath:refine-initiative`** (`plugin/skills/refine-initiative/`) — the
  layer above `refine-ticket`. Takes an initiative, reads its feature
  definitions and the tickets already under it, investigates the architecture
  and decision records those features land in, interviews the filer in batched
  concrete rounds, then rewrites the initiative's description and every feature
  so a team could build from them.

  It is deliberately bounded at both ends. It **stops short of code**: no
  file-by-file steps, no signatures, no DDL — that altitude belongs to
  `refine-ticket`, per ticket, later. And it **never starts building**, because
  that transition is one-way, locks the feature list and cuts a ticket per
  feature; there is no MCP tool for it and the skill hands back instead of
  asking for one.

  **Contract surfaces it depends on** (Abacus MCP): `get_ticket` returning
  `type`, `initiative_status`, `features` and `children`; `update_ticket`;
  `add_feature`, `update_feature`, `move_feature`; `add_comment`. A rename of
  any of them must ship with a skill update in the same release. It also relies
  on two current asymmetries, and names both rather than working around them:
  there is no delete tool for feature definitions, and `update_feature`
  replaces both fields.

  Second skill to require the Abacus MCP server, after `refine-ticket`.

- **`/colormath:plan-initiative`** (`plugin/skills/plan-initiative/`) — runs
  `refine-ticket` over every ticket in an initiative, one at a time, in build
  order, injecting what that skill cannot see on its own: the initiative and its
  settled decisions, the ticket's position in the sequence, what came before it
  and *what those plans decided*, and what comes after it.

  The reason is the seams. Run by hand seven times, `refine-ticket` grooms seven
  strangers — re-deriving the same background, asking the same question seven
  times, and producing plans that each make locally sensible choices that
  contradict each other where they meet. Answers carry forward, so the questions
  thin out as the run goes.

  A ticket counts as planned only when both `plan` and `qa_plan` are set,
  re-read from the tracker rather than assumed from the sub-skill returning.
  **Tasks are skipped by design** — that type has no plans and the tracker
  refuses to write them. It holds no `update_ticket` tool, because writing plans
  is `refine-ticket`'s job, and no `Edit`/`Write`, so it cannot touch the repo.

  **Contract surfaces** (Abacus MCP): `get_ticket` returning `type`,
  `initiative_status`, `children`, `plan` and `qa_plan`; `add_comment`. Plus the
  `refine-ticket` skill itself — the two ship together and a change to either's
  contract is a change to both.

- **`/colormath:implement-ticket`** (`plugin/skills/implement-ticket/`) — takes
  a groomed ticket from its plan to a shipped PR, closing the chain the other
  skills start: `refine-initiative` designs, `plan-initiative` plans every
  ticket, `refine-ticket` plans one, this one builds it.

  It executes the plan rather than rewriting it, and the step that earns its
  keep is the one before any code: **the plan was written against the codebase
  as it was**, so every step is walked against the repo first. Where it no
  longer holds, that is a finding for the user — silently improving a plan is
  how a reviewed decision gets replaced by an unreviewed one, and sometimes the
  right outcome is "this plan no longer holds" rather than a PR.

  Then: build on a branch at the layer the plan names, execute the ticket's **QA
  plan against the running stack** (every item observed, `⚠️` when a UI item has
  no browser, failures fixed and re-run rather than shipped with the document
  claiming they passed), `make preflight`, and hand off to `/colormath:ship`.
  Deviations land in the PR body and a ticket comment; the `plan` and `qa_plan`
  fields are left alone as the record of intent. It does not move tickets
  between lanes, because lane meaning is per board.

  A ticket with no plan is sent back to `refine-ticket` rather than planned and
  implemented in one breath, which would mean nobody ever reviewed the plan. A
  **task** is refused: that type carries no plans by design and is not code work.

  **Contract surfaces** (Abacus MCP): `get_ticket` returning `type`, `plan`,
  `qa_plan` and the parent initiative; `add_comment`. Plus `/colormath:ship` and
  `/colormath:qa`'s recon discipline.

## v3.0.0 — 2026-08-01

**MAJOR — the gates could not fail. They can now.** Every gate command is
`gate-cmd 2>&1 | tee /tmp/x.log`, and GitHub's implicit shell for a `run:`
step is `bash -e {0}` — **without `pipefail`**. The pipeline's exit status was
therefore `tee`'s, always `0`, and every gate failure in every consumer was
silently swallowed. This release makes the suite enforcing for the first time
since the `| tee` summaries landed. Expect red gates on your bump PR: they are
findings that were always there, not new rules.

### Fixed

- **`| tee` no longer masks gate exit codes** (all 22 gate steps). The
  workflow now declares `defaults.run.shell: bash`, which selects
  `bash --noprofile --norc -eo pipefail {0}`, so the gate command's status is
  the step's status. Jobs set only `defaults.run.working-directory`, which
  merges with the workflow-level `shell` per-key rather than replacing it.

  Observed in the wild before the fix: an intendent run where `pip-audit`
  reported 10 unignored CVEs and exited 1, while the job reported success. The
  file header claimed "bash runs with -o pipefail, so tee never masks a real
  failure" — that assumption was simply wrong, and is now enforced instead of
  asserted.

### Added

- **`deps-skip-unchanged` input** (boolean, default `true`). On
  `pull_request` runs, the pip-audit scan is skipped when the PR changes none
  of `poetry.lock`, `pyproject.toml`, or `.colormath/audit.conf` (compared
  three-dot against the base branch, so base-side churn doesn't count). The
  scan is ~200 sequential per-package PyPI lookups — 6m15s of a 6m30s job in
  intendent, against a suite where every other gate finishes under 2m30s — and
  its verdict is a pure function of the locked set, the allowlist, and the
  upstream advisory databases. A PR that moves neither of the first two can
  only differ by the third, which the base branch re-checks on every merge.

  **Non-PR events always run the full scan**, so merges to the default branch
  still catch newly-published advisories. A consumer wanting a nightly
  re-check just adds a `schedule:` trigger to its caller — no further config.
  Set `deps-skip-unchanged: false` to scan on every run.

  The `deps` job now checks out with `fetch-depth: 0` (merge-base needs
  history), matching `migrations` and `diff-coverage`. `make audit` is
  unchanged and always performs a full scan.

### Changed

- **The review workflow's default models and effort now target cost**
  (`.github/workflows/review.yml`). Measured on a real intendent PR, the two
  agents cost **$1.00** (review, 18 turns) and **$0.53** (test-plan, 14 turns)
  — $1.54 per pull request. Two defaults change, and consumers get both
  without editing anything:

  - **`test-plan-model` now defaults to `claude-haiku-4-5`** (previously it
    inherited `model`, i.e. Sonnet 4.6). The test-plan agent does read-only
    analysis and emits a checklist — work well inside Haiku's range — at $1/$5
    per MTok against Sonnet's $3/$15. The review agent deliberately does
    **not** move: adversarial review is where model tier buys real findings.
  - **`review-effort` now defaults to `medium`**, below the model's own
    `high`. Fewer thinking tokens and usually fewer turns, for a modest cost
    in review depth.

  Four new inputs make both tunable per agent: `review-model`,
  `test-plan-model`, `review-effort`, `test-plan-effort`. An empty model falls
  back to `model`; an empty effort passes no flag at all, leaving the model's
  own default.

  **`effort` is rejected by Haiku 4.5 and Sonnet 4.5**, so `test-plan-effort`
  defaults to empty by necessity rather than preference — setting it while
  `test-plan-model` is on the default Haiku will fail the request. Move
  `test-plan-model` to a 4.6+ model first.

  **If your caller sets `model:`**, it no longer reaches both agents:
  `test-plan-model`'s non-empty default takes precedence over the fallback.
  Set `test-plan-model` explicitly to keep one model everywhere.

### Upgrade notes

Paste into Claude Code in each consumer repo:

> Bump colormath from v2.x to v3.0.0: update the `@v2.x.x` pins in
> `.github/workflows/gates.yml` and `.github/workflows/review.yaml` to
> `@v3.0.0`, and run `make colormath-update REF=v3.0.0` so the vendored
> `Makefile.colormath` stays in lockstep with the pins.
>
> v3.0.0 fixes a bug where `| tee` masked every gate's exit code, so gates
> that were silently passing may now fail. **Run `make preflight` before
> opening the bump PR** — it mirrors CI and will surface the backlog locally.
> Triage what it finds: fix the real findings, and for anything you are not
> ready to burn down, set that gate's `enable-<gate>: false` in the caller
> (keeping `COLORMATH_PREFLIGHT_SKIP` in `Makefile.colormath` in lockstep) and
> file yourself an issue. Do not merge a bump PR with a gate disabled and no
> issue filed.
>
> Known for intendent specifically: the `deps` gate will go red on 10
> unignored `onnx` advisories and 3 `nltk` advisories (CVE-2026-12075 /
> -12061 / -12074, fixed in nltk 3.10.0). Bump nltk; for onnx, either bump to
> 1.22.0 or add the ids to `.colormath/audit.conf` with a justification and a
> revisit trigger.
>
> No input was renamed or removed and no gate default flipped, so the gate
> half of the bump is mechanical — that work is entirely in the findings it
> uncovers.
>
> The review workflow does change behavior on this bump, with no action
> needed: the test-plan agent moves to Haiku and the reviewer drops to
> `medium` effort, roughly halving review spend per PR. Two cases need a
> caller edit — if you set `model:` and want it to apply to both agents, add a
> matching `test-plan-model:`; and if you want the test-plan agent at a
> non-default effort, move `test-plan-model:` to a 4.6+ model first, because
> Haiku 4.5 rejects the effort parameter.

## v2.4.0 — 2026-07-31

**MINOR — new `/colormath:review-ticket` skill; no consumer CI changes.** Purely
additive: a new plugin skill, which LIFECYCLE classifies as MINOR. Nothing a
consumer runs changes behavior, and the existing skills are untouched.

### Added

- **`/colormath:review-ticket` — groom a ticket until it can be worked**
  (`plugin/skills/review-ticket/`). Fills the gap *before* the pipeline starts:
  `bugfix` turns a reported defect into a fix, `qa` sweeps for unknown ones, and
  `ship` carries a finished branch through the PR — but none of them help with a
  one-line ticket nobody can act on. The skill reads the ticket and its full
  comment thread, does a real code pass **before** asking anything, then asks the
  few concrete questions whose answers change the outcome, and writes back a
  standalone description, an implementation plan whose every step names a real
  path, and a QA plan whose every item a person could execute without asking
  what it meant.

  Two failure modes drove the wording. **Fluent restatement** — expanding a
  title into confident prose and generic steps ("update the relevant service")
  that could have been written without opening the repo — is countered by
  ordering investigation ahead of questions and by the rule that a plan step
  naming no file is a wish. **Interrogation** — a dozen open-ended questions
  that cost the filer more than writing the ticket themselves — is countered by
  the one-batch cap (two rounds absolute maximum), concrete multiple choice via
  `AskUserQuestion`, and the instruction to take a conventional default and
  record it as a stated assumption rather than spend a question on it.

  Step 2 hunts specifically for **what makes a ticket non-trivial**, because the
  expensive miss is a one-line code change whose real work sits outside the diff
  — a DNS record, a verified vendor identity, a migration ordering constraint, a
  deploy that must reach two services. It also checks the repo's recorded
  decisions, so a ticket asking for something an ADR explicitly rejected gets
  caught during grooming rather than during review.

  The skill grooms and stops: no branches, no code edits, and no creating,
  splitting, moving or re-typing tickets as a side effect — an oversized ticket
  gets a recommended split and the call stays with the user. When investigation
  shows the ticket shouldn't be done at all, that finding is the deliverable
  instead of a plan for work nobody needs.

### Contract surfaces

- **New dependency: the Abacus MCP server** — the plugin's first tracker
  dependency. `review-ticket` keys on `mcp__abacus__get_ticket`,
  `update_ticket`, `add_comment`, `list_boards` and `list_tickets`, on ticket
  **keys** (`CM-00001`) as the identifier, and on Abacus's split of
  `description`, `plan` and `qa_plan` into three separate fields — the skill
  writes all three, because Abacus marks a story ready only once both `plan`
  and `qa_plan` are set, so folding QA into the plan field leaves the ticket
  looking unready. A rename of any of those tools or fields must ship with a
  skill update in the same release. No other skill touches Abacus, and no
  consumer CI does.

## v2.3.0 — 2026-07-24

**MINOR — `/colormath:ship` no longer re-triggers the review; adds an explicit
merge-decision gate. No consumer CI changes.** Only skill instructions change;
nothing a consumer runs behaves differently.

### Fixed

- **`ship` could loop forever between review and QA.** Step 5 told the agent to
  comment `@claude` for a fresh review whenever its fixes were "substantive".
  But the review workflow runs the test-plan agent alongside the reviewer, so
  every re-review produced a *new* test plan, which demanded a *new* full round
  of UI + API QA, whose fixes again looked substantive. Observed in practice on
  a real PR: the agent completed a full browser QA pass, posted its checklist,
  requested a re-review, and was immediately asked for another QA round. The
  "cap this at one re-trigger round" wording was too weak to stop it.

  There is now exactly **one** review per ship run. Step 5 states the failure
  mode explicitly and forbids `@claude` re-triggers, and a new Rules entry
  ("One review per run") repeats it. Findings added later by a *human* reviewer
  are still read and addressed — the rule only bars summoning another automated
  review.

### Changed

- **Step 7 is now "Merge decision", not "Final review"** — it judges what the
  run already produced (the single review, the Addressed/Not-changed response,
  the QA results, the gates on the latest commit) rather than implying another
  review pass. Three explicit gates:
  1. the thermonuclear review raised **no Blockers** — if it did, a human signs
     off, *even when the agent already fixed it*;
  2. every finding is fixed or dismissed with a written reason, gates green;
  3. QA ran with no `❌` standing, and **every `⚠️` carries a stated, sound
     reason**.
- **Explainable QA gaps no longer block the merge.** The old gate failed on any
  `⚠️`, which punished correct judgment — e.g. skipping `make clean` precisely
  *because* it would destroy the working dev database. A `⚠️` now passes when
  the reason is stated and sound, and still blocks when it is "didn't get to
  it", an undrivable UI item, or a stack that wouldn't come up.

## v2.2.0 — 2026-07-24

**MINOR — new `/colormath:bugfix` skill; no consumer CI changes.** Purely
additive: a new plugin skill, which LIFECYCLE classifies as MINOR. Nothing a
consumer runs changes behavior, and the existing skills are untouched.

### Added

- **`/colormath:bugfix` — a bug report, all the way to a merged fix**
  (`plugin/skills/bugfix/`). Fills the gap on the front of the pipeline:
  `/colormath:qa` sweeps a feature area for *unknown* problems and `ship` takes
  an already-fixed branch through the PR, but neither turns a *specific
  reported* defect into a fix. The skill reads the report (prose, a pasted
  stack trace or log excerpt, or a path to a written-up report file), then
  works six steps — establish the facts the report omitted (environment,
  surface, literal repro, privilege tier, blast radius) via one batched round
  of concrete `AskUserQuestion` options informed by a fast code pass first;
  reproduce against the running stack at the reporter's surface and tier;
  diagnose to the layer the invariant belongs at, enumerating sibling entry
  paths; fix with a regression test whose fail-then-pass ordering is actually
  verified; remediate already-corrupted stored data as an idempotent migration
  in the same PR (including the constraint-trap check, where a new
  `NOT NULL`/`CHECK`/unique index meets existing violating rows); then commit
  to `fix/<slug>`, run `make preflight`, and hand off to `/colormath:ship`.

  Two refusals are deliberate and load-bearing: it **never modifies
  production** — production reports are reproduced locally by constructing data
  in the shape the report implies, and remediation lands through the PR — and
  when it cannot reproduce, it **stops and reports** what it tried, ruled out,
  and needs, rather than shipping a fix that's reasoned instead of observed.
  This mirrors ship's "when in doubt, hold".

  Contract surfaces it depends on — a rename of any must ship with a matching
  skill update: the sibling `qa` skill's `references/recon.md` (step 2's stack
  bring-up + credential tiers), the `make preflight` endpoint, and the
  `/colormath:ship` skill name for the step-6 handoff.

- Plugin bumped to `2.2.0`; marketplace blurb notes the new skill.

## v2.1.0 — 2026-07-23

**MINOR — `/colormath:ship` gains test-plan execution and can now auto-merge;
no consumer CI changes.** Nothing a consumer runs turns red without them
editing anything (the `test-plan` job already ships in the review workflow
since v2.0.0). But note the **behavior change**: where `ship` previously stopped
at a merge *recommendation* and never merged, it now fixes findings itself
(blockers included) and, when the PR is genuinely clean, **merges it**. Repos
without the review workflow are unaffected — the skill detects its absence,
skips QA, and its final review holds rather than merging a PR it couldn't
verify.

### Changed

- **`/colormath:ship` now executes the PR's test plan** (`plugin/skills/ship/`).
  A new step 4 waits for the `review / test-plan` check, reads the `## Test
  Plan` comment and its machine-readable verdict (`qa_depth` / `requires_ui_qa`
  / `requires_api_qa`), runs the UI/API QA checklists against the **running**
  stack — reusing the `qa` skill's recon + verify discipline, scaling effort by
  `qa_depth`, driving a browser for UI items when one is reachable and marking
  them `⚠️` unverified when not — then posts a `## Test Plan · Results` comment
  checking off each item with the evidence it observed. A new step 6 restores
  any local state the run mutated. The skill's `allowed-tools` widen to broad
  `Bash` + `Write` + `Skill` + `AskUserQuestion` (step 4 drives the local stack,
  which no narrow `gh`/`git` allowlist covers); `model` is unchanged.

- **`/colormath:ship` now fixes findings automatically and gates the merge, not
  the fix.** The old SMALL/LARGE triage is gone. Step 5 fixes every review and
  `❌` QA finding it can — **Blockers included, without asking** — in iterative
  rounds (re-verify each repro against the running system; re-trigger the review
  with `@claude` once when fixes are substantive), deferring only findings that
  genuinely need a human (a design decision, or a `CHANGES_REQUESTED` structural
  call). A new **step 7 "final review"** then decides: if no blockers stand
  *and* QA was performed and passed, it posts a comment and **auto-merges**
  (`gh pr merge`, honoring the repo's merge convention); if either is false —
  a standing blocker, a finding deferred to a human, or QA that failed or
  couldn't run (e.g. a required UI item with no browser) — it posts *why* it
  held off and stops, leaving the merge to a human. The former hard rule "never
  merge" is replaced by this gated auto-merge; "never push to the default
  branch" still holds (a `gh pr merge` is not a push to `main`).

  Contract surfaces it depends on — a rename of any must ship with a matching
  skill update: the review workflow's `review / test-plan` check name, the
  `## Test Plan` comment marker with its `<!-- colormath-test-plan -->` /
  `<!-- testplan … -->` hidden markers and the `qa_depth` / `requires_ui_qa` /
  `requires_api_qa` verdict fields, the sibling `qa` skill's `references/`
  (recon + probe catalogs), and — as before — the `gates / *` check names, the
  `review / review` check, and the `## Thermonuclear Review` marker.

- Plugin bumped to `2.1.0`; marketplace blurb notes `/colormath:ship` now
  executes the generated test plan and auto-merges when clean.

## v2.0.0 — 2026-07-23

**MAJOR — two formerly opt-in gates flip default-on.** `migrations` (shipped
opt-in in v1.1.0) and `import-linter` (added and promoted in this same
release) now default `enable-*: true`. A consumer that never set these flags
gets both gates on its next bump: `migrations` just works wherever
`migrations-path` (`alembic/versions`) exists; `import-linter` fails until the
repo has `[tool.importlinter]` contracts, so disable it and burn down on your
schedule. This is the promotion the v1.1.0 changelog and the new-gate rollout
rule pointed at.

### Added

- **`import-linter` gate** (import-linter): enforces the project's import
  architecture — layered dependency order, forbidden edges, module
  independence — via `lint-imports`. Pure static analysis (grimp builds the
  import graph without executing code), so no project deps are installed,
  mirroring `docstrings`/`templates`. The contracts are entirely
  project-specific and come from `[tool.importlinter]` in the consumer's
  pyproject (or a `.importlinter` file), which `lint-imports` auto-discovers.
  New inputs: `import-linter-spec` (`"import-linter>=2,<3"`) and
  `enable-import-linter` (**default `true`**). Flat-layout note: `root_packages`
  takes packages (dirs with `__init__.py`), so to forbid a top-level single-file
  module (e.g. a `shared.py`) set `include_external_packages = True` and name it
  in `forbidden_modules`.
- `Makefile.colormath`: `import-linter` target with a
  `COLORMATH_IMPORT_LINTER_SPEC` knob, now part of `preflight`.
- `example/`: an `example_pkg` (service + web layers) with a `[tool.importlinter]`
  `forbidden` contract (service must not import web) and a covering test;
  colormath's self-test runs the gate default-on.
- **`/colormath:qa` plugin skill** (`plugin/skills/qa/`): QAs a focus area
  against the running stack, then hands the fixes to `/colormath:ship`.
  Recon (bring the stack up without disturbing existing state; collect
  credentials at several privilege tiers) → probe → verify → ranked findings
  the user selects from → fix → restore → ship. Three probe catalogs live in
  `references/`: `security.md` (authorization matrix, confused-deputy,
  stored content served back, input validation, disclosure), `correctness.md`
  (cross-surface consistency, write round-trips, boundaries, contract drift),
  `accessibility.md` (keyboard, semantics, dynamic state, contrast).

  Contract surfaces it depends on — a rename of any must ship with a matching
  skill update: the `ship` skill (step 7 handoff), `make preflight` and the
  `gates / *` check names (step 4, telling a real finding from local
  tool-version drift), and the `a11y` gate as the documented floor that the
  accessibility catalog deliberately goes beyond. It also assumes the
  consumer documents run commands and ports in `AGENTS.md` / `CLAUDE.md`.

### Changed

- **`enable-migrations` and `enable-import-linter` now default `true`.** These
  were the last two opt-in gates; every gate is now default-on. Disable any
  that are red for your repo (`enable-<gate>: false`) and burn down on your
  own schedule.
- `Makefile.colormath`: `migrations` and `import-linter` join `preflight`, so
  the local mirror matches the default-on CI suite. Keep
  `COLORMATH_PREFLIGHT_SKIP` in lockstep with your caller's `enable-*: false`.
- **Plugin metadata aligned to the release.** `plugin/.claude-plugin/plugin.json`
  bumps `1.0.0` → `2.0.0` (it was last set at the v1.0.0 release and missed the
  `qa`-skill bump), and the marketplace blurb now names `/colormath:qa`. The
  plugin marketplace tracks the default branch, so this ships to installs on the
  next auto-update — no consumer action.

### Upgrade notes

Paste into Claude Code in each consumer repo:

> Bump colormath to v2.0.0: update the `gates.yml` `uses:` pin (and
> `review.yml`/`review.yaml` if present) to `@v2.0.0` and run
> `make colormath-update REF=v2.0.0` (refreshes Makefile.colormath AND
> eslint.config.colormath.mjs). Two gates flip default-on at v2.0.0:
> `migrations` and `import-linter`. If this repo uses alembic (has
> `alembic/versions`), leave `migrations` on — it needs no config; otherwise
> add `enable-migrations: false`. Unless this repo already has a
> `[tool.importlinter]` contract, add `enable-import-linter: false` and file
> yourself an issue to write import contracts later. Mirror every newly
> disabled gate in `COLORMATH_PREFLIGHT_SKIP` in the root Makefile (before the
> include) so `make preflight` matches CI. Verify locally: `make preflight`
> (or the individual `make migrations` / `make import-linter` targets),
> `poetry check --lock`, then open the bump PR.

## v1.1.0 — 2026-07-10

MINOR: new gate, shipped **opt-in** per the new-gate rollout rule — existing
consumers see a skipped `migrations` job until they set
`enable-migrations: true`; promotion to default-on comes with the next MAJOR.

### Added

- **`migrations` gate** (`scripts/migrations-sync.sh`, pure git — no project
  deps): fails when the base branch has alembic migration changes the PR
  branch predates, before they merge into multiple alembic heads. Diffs the
  base branch against its merge-base with the PR head (checked out at the
  real head SHA — the ephemeral merge commit would hide divergence), scoped
  to the migrations directory, and tells the author to
  `git pull --rebase origin <branch>`. The base branch is the
  `default-branch` input when set, else the repo's default branch (main and
  master both work); local runs discover it from `origin/HEAD`. New inputs:
  `migrations-path` (`"alembic/versions"`) and `enable-migrations`
  (**default `false`**).
- `Makefile.colormath`: `migrations` target (fetch-then-run of the shared
  script) with a `COLORMATH_MIGRATIONS_PATH` knob. Not in `preflight` while
  the CI gate is opt-in.
- `example/`: reference `alembic/versions/` directory (excluded from
  interrogate + coverage, mirroring real consumers); the self-test runs with
  `enable-migrations: true`.

## v1.0.0 — 2026-07-10

**MAJOR — pins are now contractual.** Two breaking changes: every gate now
defaults **on** (the five formerly-opt-in gates — `docstrings`, `jslint`,
`templates`, `js-deps`, `dockerfile` — flip to `enable-*: true`), and the
`jslint` contract now expects the vendored shared eslint base.

### Added

- **`eslint.config.colormath.mjs`**: the shared eslint base, vendored by
  consumers alongside `Makefile.colormath` (both refreshed by
  `make colormath-update`). Exposes a `colormathConfig()` factory —
  `files`, `testFiles`, `cdnGlobals`, `rules` — with appended flat-config
  blocks as the escape hatch (later entries win) and ejecting as sanctioned
  divergence. Consumer `eslint.config.js` becomes a thin caller; devDeps
  contract: `eslint`, `@eslint/js`, `globals`.
- `Makefile.colormath`: `COLORMATH_PREFLIGHT_SKIP` knob — `preflight` now
  runs the full fourteen-gate mirror minus the listed targets; keep it in
  lockstep with your caller's `enable-*: false` flags.

### Changed

- All `enable-<gate>` inputs default `true`. A consumer that never set the
  opt-in flags gets five new gates on its next bump — disable any that are
  red and burn down on your schedule.
- `colormath-update` refreshes both vendored files.

### Upgrade notes

Paste into Claude Code in each consumer repo:

> Bump colormath to v1.0.0: update the `gates.yml` `uses:` pin (and
> `review.yaml` if present) to `@v1.0.0` and run
> `make colormath-update REF=v1.0.0` (now refreshes Makefile.colormath AND
> eslint.config.colormath.mjs). All gates default on at v1.0.0: delete any
> now-redundant `enable-*: true` lines, and add an explicit
> `enable-<gate>: false` for every gate this repo isn't ready for (check the
> caller's comments for the current burn-down list — at minimum `templates`
> everywhere, plus `styles`/`a11y` in runwayz). Set
> `COLORMATH_PREFLIGHT_SKIP` in the root Makefile (before the include) to
> the same list so `make preflight` mirrors CI. Rewrite `eslint.config.js`
> as a thin caller of the vendored base per its header — move this repo's
> CDN globals into `cdnGlobals`, file globs into `files`, and keep any
> special-file blocks (e.g. worklet globals) as appended entries; ensure
> devDeps `eslint`, `@eslint/js`, `globals`. Verify locally:
> `npm run jslint`, `poetry check --lock`, `make audit`, then open the bump
> PR.

## v0.6.0 — 2026-07-10

MINOR: four new gates, all shipped **opt-in** per the new-gate rollout rule —
existing consumers see skipped jobs until they set the `enable-*` inputs;
promotion to default-on comes with the next MAJOR. One caveat below on the
`tests` gate (allowed while on `0.x`).

### Added

- **`jslint` gate** (eslint): lints hand-written JS via a consumer-defined
  `jslint` npm script — closes the asymmetry where Python gets ruff and CSS
  gets stylelint but JS only gets tests. New input: `enable-jslint`
  (**default `false`**). Consumer contract: npm script `jslint` +
  `eslint.config.js` (reference in `example/`).
- **`templates` gate** (djlint): lints the Jinja templates themselves —
  unbalanced tags, malformed syntax — complementing `a11y`, which validates
  the HTML but not the Jinja. Pure scan, no project deps; profile and rule
  ignores come from `[tool.djlint]` in the consumer's pyproject. New inputs:
  `djlint-spec` (`"djlint>=1.36,<2"`), `djlint-paths` (`"templates/"`), and
  `enable-templates` (**default `false`**).
- **`js-deps` gate** (npm audit): the JS half of "audit what ships" — audits
  `package-lock.json` with `--omit=dev`, so dev tooling never fails the gate.
  Skips quietly when the workdir has no lockfile. New inputs:
  `npm-audit-level` (`"high"`) and `enable-js-deps` (**default `false`**).
- **`dockerfile` gate** (hadolint): static Dockerfile lint, pinned binary
  (same install pattern as gitleaks). New inputs: `hadolint-version`
  (`"2.14.0"`), `hadolint-dockerfiles` (`"Dockerfile"`), and
  `enable-dockerfile` (**default `false`**).
- `Makefile.colormath`: mirror targets `jslint`, `templates`, `js-audit`,
  `dockerfile` (out of `preflight` while their gates are opt-in) and
  `lock-check` (in `preflight`), with `COLORMATH_DJLINT_SPEC` /
  `COLORMATH_DJLINT_PATHS` / `COLORMATH_NPM_AUDIT_LEVEL` /
  `COLORMATH_HADOLINT_DOCKERFILES` knobs.
- `example/`: `eslint.config.js` + `jslint` npm script, `[tool.djlint]`
  (jinja profile, H030/H031 ignored), and a hadolint-clean `Dockerfile`;
  colormath's self-test enables all four new gates.

### Changed

- **`tests` gate now runs `poetry check --lock` first**, so pyproject/lock
  drift fails up front with a legible message instead of deep inside a
  `poetry install`. Strictly this can turn a drifted consumer red without a
  consumer edit (MAJOR territory) — landed on `0.x` where breaking changes
  are allowed; the fix is `poetry lock` in the consumer repo.

## v0.5.0 — 2026-07-09

MINOR: new gate, shipped **opt-in** per the new-gate rollout rule — existing
consumers see a skipped `docstrings` job until they set
`enable-docstrings: true`; promotion to default-on comes with the next MAJOR.

### Added

- **`docstrings` gate** (interrogate): docstring-coverage check, promoted
  from runwayz's project-specific sibling job. Pure AST scan, no project
  deps; threshold and scope come from `[tool.interrogate]` in the consumer's
  pyproject. New inputs: `interrogate-spec` (`"interrogate>=1.7,<2"`),
  `interrogate-paths` (`"."`, scoped by the pyproject excludes), and
  `enable-docstrings` (**default `false`**).
- `Makefile.colormath`: `docstrings` target with
  `COLORMATH_INTERROGATE_SPEC` / `COLORMATH_INTERROGATE_PATHS` knobs. Not in
  `preflight` while the CI gate is opt-in.
- `example/`: `[tool.interrogate]` (fail-under 100) and full docstring
  coverage; colormath's self-test runs with `enable-docstrings: true`.

## v0.4.0 — 2026-07-09

MINOR: new opt-in artifact — the plugin channel (channel D) opens.

### Added

- **Claude Code plugin marketplace** (`.claude-plugin/marketplace.json`) and
  the **`colormath` plugin** (`plugin/`), extracted from intendent's local
  `.claude/skills/`. First skill: **`/colormath:ship`** — take the current
  branch through the PR pipeline (open PR, watch the `gates / *` checks,
  wait for the Thermonuclear Review / formal reviews, triage SMALL vs LARGE,
  apply small fixes with an Addressed/Not-changed response comment) and stop
  at a merge recommendation, never merging. Generalized from the intendent
  version: default-branch-agnostic, detects whether the repo runs the
  colormath review workflow (skips the review wait when absent), and drops
  `--required` from the gate watch (repos without branch protection get
  "no required checks" + exit 1 from gh).
  - Install: `/plugin marketplace add ColorMath/ci` then
    `/plugin install colormath@colormath`, or per-repo via
    `extraKnownMarketplaces`/`enabledPlugins` in `.claude/settings.json`
    (example in the README).

## v0.3.0 — 2026-07-09

MINOR: new opt-in artifact; existing consumers are unaffected until they add
a caller for it.

### Added

- **Reusable AI review suite** (`.github/workflows/review.yml`,
  `workflow_call`), extracted from intendent's `claude-review` workflow. Two
  parallel agents on every non-draft PR (re-runnable via `@claude` comment):
  the adversarial "Thermonuclear Review" (tracking comment led by the
  `## Thermonuclear Review` marker + inline comments) and the QA test-plan
  agent (`## Test Plan` comment; machine-readable
  `qa_depth`/`requires_ui_qa`/`requires_api_qa` exposed as workflow outputs,
  with placeholder `api-qa`/`ui-qa` jobs gating on them).
  - Inputs: `model`, `review-focus` (project-specific reviewer emphasis —
    replaces intendent's hardcoded Google Drive note), `enable-review`,
    `enable-test-plan`. Secret: `anthropic_api_key` (required).
  - The hidden test-plan marker is now `<!-- colormath-test-plan -->`
    (was `<!-- intendent-test-plan -->`); the human-visible markers are
    unchanged, so automation keyed on `## Thermonuclear Review` /
    `## Test Plan` keeps working.

## v0.2.1 — 2026-07-09

PATCH: `Makefile.colormath` robustness fixes, from intendent's adoption
review. Refresh vendored copies with `make colormath-update REF=v0.2.1`.

### Fixed

- `sast` target: `pip install`/`bandit` now run via `poetry run`, so bandit
  lands in the project venv instead of whatever pip is on PATH.
- `secrets` target: restored the actionable "gitleaks not installed" guard.
- `audit`/`coverage-diff` targets: fetch-then-run with `curl --retry 3` and a
  distinct error message when the script fetch fails, so a network failure is
  no longer indistinguishable from a gate failure.

## v0.2.0 — 2026-07-09

MINOR: new opt-in artifact; existing consumers are unaffected until they
vendor it.

### Added

- **`Makefile.colormath`**: shared local mirrors of every gate, so all
  consumers expose the same `make` endpoints (`format-check`, `lint`,
  `typecheck`, `styles`, `sast`, `secrets`, `a11y`, `audit`,
  `coverage-diff`, `preflight`). Consumers vendor it at a pinned tag and
  `include` it from their Makefile, providing a `test` target and optional
  `COLORMATH_*` overrides (`BANDIT_SPEC`, `RUFF_CHECK_ARGS`,
  `DIFF_COVER_BASE`, `DIFF_COVER_FAIL_UNDER`). `make colormath-update
  REF=vX.Y.Z` refreshes the vendored copy; the file's `COLORMATH_REF` is
  stamped per release like the workflow's `colormath-ref`.

## v0.1.1 — 2026-07-09

PATCH: keeps green things green.

### Changed

- Repo transferred from `craigmbooth/colormath` to `ColorMath/ci`. All
  internal checkout refs, docs, and the stamped `colormath-ref` now use the
  new path. GitHub redirects the old path, so `v0.1.0` pins keep working —
  but pin `ColorMath/ci/...@v0.1.1` going forward.

## v0.1.0 — 2026-07-08

Initial release: the CI gates channel.

### Added

- **Reusable gate suite** (`.github/workflows/gates.yml`, `workflow_call`):
  nine parallel gates — ruff, tests (JS + Python), typecheck (mypy), styles
  (stylelint), sast (bandit), secrets (gitleaks), a11y (html-validate), deps
  (pip-audit), diff-coverage (diff-cover). Reconciled from the
  intendent/talas lineage (newest action pins, talas's full ruff lint +
  pipx-pinned Poetry, intendent's job summaries).
  - Inputs: `python-version`, `node-version`, `default-branch` (falls back to
    the repo default), `workdir`, `poetry-install-args`, `ruff-spec`,
    `ruff-select`, `bandit-spec`, `gitleaks-version`,
    `diff-cover-fail-under`, `free-disk-space`, and per-gate `enable-*`
    booleans for incremental adoption.
  - Consumer contract: `.colormath/audit.conf`, optional `.colormath/ci.env`
    and `.colormath/ci-extra-install.sh`, optional `.gitleaks.toml`,
    `[tool.bandit]` in pyproject, npm scripts `test`/`styles`/`a11y`.
- **Composite actions**: `setup-python-poetry` (pipx-pinned Poetry, cached
  in-project venv), `setup-node` (npm cache, skips gracefully without
  package.json), `gate-summary` (the per-gate `$GITHUB_STEP_SUMMARY` block).
- **Gate scripts**: `scripts/diff-coverage.sh` (base branch + threshold via
  env) and `scripts/audit-deps.sh` (poetry groups + CVE allowlist from the
  consumer's `.colormath/audit.conf`). Fetched by the workflow at its own
  matching ref — consumers never copy them.
- **example/**: minimal compliant consumer; colormath's own CI runs the full
  suite against it on every PR.
- Docs: README (adoption guide per product), LIFECYCLE (versioning, release
  checklist, propagation).
