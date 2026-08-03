# colormath plugin

Claude Code skills for repos built on the colormath (ColorMath/ci) shared
infrastructure. Install via the marketplace at the repo root — see the
[main README](../README.md#optional-claude-code-plugin) — then invoke each
skill as `/colormath:<skill>`.

Skills here encode the colormath *contract* — gate check names, comment
markers, make endpoints. That's the test for whether a skill belongs in this
plugin: if it would work in any repo, it goes elsewhere; if it greps for
`gates / *` or `## Thermonuclear Review`, it lives here, so a release that
changes the contract ships the matching skill change in the same diff.

## `/colormath:ship` — PR pipeline end to end

Takes the current branch through the full PR pipeline and stops at a
recommendation:

1. **Open the PR** — pushes the branch, creates the PR (`gh pr create`) with a
   diff-summarizing body; takes an optional PR title as its argument.
2. **Watch the gates** — polls until every `gates / *` check is green; on a
   red gate it reads the failing job's logs, fixes the cause on the branch,
   pushes, and re-watches.
3. **Wait for review** — if the repo calls colormath's review workflow, waits
   for the `review / review` check and reads the `## Thermonuclear Review`
   comment (plus any formal/human reviews and inline comments — full bodies,
   never truncated). Skips this wait, and says so, in repos without the
   review workflow. Knows the review's failure modes (e.g. the
   workflow-validation guard when a PR edits the review caller itself) and
   reports them instead of treating silence as a clean review.
4. **Execute the test plan** — waits for the `review / test-plan` check, reads
   the `## Test Plan` comment and its machine-readable verdict (`qa_depth` /
   `requires_ui_qa` / `requires_api_qa`), then runs the UI/API QA checklists
   against the **running** stack — reusing the `qa` skill's recon + verify
   discipline, scaling effort by `qa_depth`, driving a browser for UI items
   when one is reachable and marking them `⚠️` unverified when not. Posts a
   `## Test Plan · Results` comment checking off each item with the evidence it
   observed; `❌` findings feed the fixes in step 5. Skipped in repos without
   the review workflow.
5. **Fix every finding — blockers included** — fixes every review finding and
   every `❌` QA finding it can, **without asking**, in iterative rounds
   (re-verifying each repro against the running stack, re-triggering the review
   with `@claude` once when fixes are substantive), and posts the **Addressed /
   Not changed** response comment. Only findings that genuinely need a human — a
   design decision, or a `CHANGES_REQUESTED` structural call — are deferred.
6. **Restore** — undoes any local state step 4 mutated (rows, files, minted
   credentials, flipped config), and shows you the restored baseline.
7. **Final review — auto-merge or hold** — if no blockers stand *and* QA was
   performed and passed, posts a comment and **auto-merges** the PR
   (`gh pr merge`, honoring the repo's merge convention). If either isn't true —
   a standing blocker, a finding deferred to a human, or QA that failed or
   couldn't run — it posts *why* it held off and stops, leaving the merge to
   you.

Hard rules baked in: it never pushes to the default branch, and it merges
**only** from the gated step-7 final review (both conditions satisfied, with a
PR comment first) — otherwise it holds and explains.

**Prerequisites:**

- An authenticated `gh` CLI with push access to the repo.
- The colormath gates caller (`.github/workflows/gates.yml`) — step 2 keys on
  the `gates / *` check names it produces.
- Optional: the colormath review caller (job named `review`, per the adoption
  docs) — step 3 keys on the `review / review` check and the
  `## Thermonuclear Review` comment marker; step 4 keys on the
  `review / test-plan` check and the `## Test Plan` comment (with its
  `<!-- colormath-test-plan -->` / `<!-- testplan … -->` verdict markers).
- For step 4, a locally runnable stack (run commands + ports in
  `AGENTS.md` / `CLAUDE.md`) and seeded accounts — same prerequisites as
  `/colormath:qa`, whose `references/` it reuses. A browser is optional: UI
  checklist items are driven through one when reachable and marked `⚠️`
  unverified when not.
- The skill's `allowed-tools` are broad (`Bash`, plus read/edit/write, `Skill`,
  `AskUserQuestion`) because step 4 drives the local stack, which no narrow
  `gh`/`git` allowlist covers; consumer repos can mirror that in
  `.claude/settings.json` permissions to avoid prompts (see intendent for a
  worked example).

## `/colormath:qa` — QA a feature, then ship the fixes

Takes a focus area (`/colormath:qa the invite flow`) and QAs it against the
**running** stack, on the principle that a finding is a claim about a running
system and only counts once you've reproduced it:

1. **Scope** — maps the area to the routes, services, jobs and templates that
   implement it, and notes the trust boundaries it crosses.
2. **Recon** — brings the stack up (checking first whether it's already
   running, so it doesn't reseed someone's working environment) and collects
   credentials at *several* privilege tiers, including cross-tenant and any
   no-access role. A single admin account can't surface an authorization bug.
3. **Probe** — works three catalogs in `references/`: security (authorization
   matrix, confused-deputy, stored content served back, input validation),
   correctness (cross-surface consistency, write round-trips, contract drift),
   accessibility (keyboard, semantics, announcements, contrast). Sweeps before
   fixing anything.
4. **Verify** — reproduces every finding and reports the mechanism actually
   observed, not the assumed one. Separates pre-existing failures from real
   ones before attributing anything.
5. **Report and choose** — ranked findings with blast radius and repro, plus
   what came back clean and what wasn't covered; you pick what to fix.
6. **Fix, restore, ship** — re-runs each original repro against the running
   system (a green unit test isn't proof the bug is gone), undoes its test
   data and config changes, then hands off to `/colormath:ship`.

Local state is fair game — it writes rows, uploads files, mints credentials —
but it stops and asks before anything leaves the machine, because a dev `.env`
often holds a live provider key.

**Prerequisites:**

- A locally runnable stack, with the run commands and ports documented in
  `AGENTS.md` / `CLAUDE.md` (the skill reads these first).
- Seeded demo data with known accounts, ideally at several privilege tiers.
- `make preflight` and the `gates / *` check names — step 4 uses them to tell
  a genuine finding from local tool-version drift, and defers to CI when the
  two disagree.
- `/colormath:ship` for the handoff in step 6.

## `/colormath:bugfix` — a bug report, all the way to a merged fix

Takes a bug report (`/colormath:bugfix users can't log in with the account
they just created`) and carries it end to end, on the principle that a report
is *evidence, not a specification* — the expensive failure is forming a
plausible theory and proving it against the wrong environment or surface:

1. **Read the report, find what's missing** — separates what the report states
   from what you'd be assuming, and asks about the gaps that actually change
   the next action: which environment (production / staging / local / CI),
   which surface, the literal input and observed-vs-expected result, which
   privilege tier, when it started, and whether it's still producing bad data.
   Does a fast code pass *first* so the questions are concrete multiple choice
   rather than open interrogation, and batches them into one round. Skips the
   round entirely when the report is already reproducible as written.
2. **Reproduce against the running stack** — reuses the `qa` skill's
   `references/recon.md` for bringing the stack up without disturbing existing
   state and for credentials at the tier the report names, then drives the
   failure at the same surface over the real transport. For production
   reports it works the local/prod delta explicitly — configuration, data
   written before a constraint existed, migration state, scale — since that
   delta is frequently the bug. **Never modifies production.** If it can't
   reproduce, it stops and reports what it tried and ruled out rather than
   shipping a speculative fix.
3. **Diagnose the defect, not the symptom** — traces back from where the error
   surfaced to where the invariant went unenforced, and picks the *layer* to
   fix at so the bug can't re-enter through a sibling path (a check on one form
   leaves every other route in; the service chokepoint closes all of them).
   Enumerates those siblings and confirms the fix covers them.
4. **Fix with a regression test that earns its keep** — test at the layer the
   fix lives at, with the fail-then-pass ordering actually verified (stash the
   fix, watch it go red), then re-runs the original repro against the running
   stack, because a green unit test only proves the case you thought of.
5. **Remediate data the defect already corrupted** — characterizes affected
   rows with a real query, catches the constraint trap (a new `NOT NULL` /
   `CHECK` / unique index against existing violating rows fails or locks users
   out), puts the mechanically-repairable part in the same PR as an idempotent
   migration tested against locally-constructed broken data, and hands over
   what no script can recover instead of guessing at it.
6. **Ship** — commits to `fix/<slug>`, runs `make preflight` once, then hands
   off to `/colormath:ship` with a PR body carrying the report, the repro, the
   cause, why the fix sits at that layer, and the remediation.

**Prerequisites:**

- A locally runnable stack with run commands and ports in `AGENTS.md` /
  `CLAUDE.md`, and seeded accounts at several privilege tiers — same
  prerequisites as `/colormath:qa`, whose `references/recon.md` step 2 reads.
- `make preflight` (step 6) and `/colormath:ship` for the handoff.
- A browser is optional but makes UI-surface reproduction far more direct.

## `/colormath:review-ticket` — groom a ticket until it can be worked

Takes a ticket key (`/colormath:review-ticket CM-00001`) and turns a one-line
reminder into something someone could pick up cold, on the principle that a
ticket is *a reminder, not a specification* — it carries the trigger its author
wrote down and none of the context they had in their head:

1. **Read the ticket and everything attached** — description, existing plan,
   every comment (where already-made decisions hide), type, swimlane, project
   contents. An existing plan means revising, not authoring.
2. **Investigate the code before asking anything** — does it already exist, or
   was it deliberately rejected by a recorded decision; which files actually
   change; is the ticket's own wording precise; is this one ticket or several.
   Then hunts specifically for **what makes it non-trivial**, since a one-line
   code change often hides the real work outside the diff — a DNS record, a
   verified vendor identity, a deploy that must reach two services.
3. **Ask only what changes the outcome** — concrete multiple choice rather than
   an open survey, because step 2 already happened; batched into one round, two
   at the ceiling. Where a conventional default exists it takes it and writes
   the assumption into the ticket instead of spending a question.
4. **Description that stands alone** — context, why it matters, acceptance
   criteria as observables a third person could check, and what's out of scope.
5. **Implementation plan someone could follow** — prerequisites and blockers
   first, then ordered steps naming **real paths** (a step that names no file is
   a wish), the layer the change belongs at, what explicitly *doesn't* change,
   and the open questions that survived.
6. **QA plan someone can execute** — happy path, authorization and tenancy, the
   edges the change introduces, regression surface, data written under the old
   behavior, accessibility, post-deploy checks; then splits what the test suite
   covers from what needs hands, and names the gates the change implicates.
7. **Show, confirm, write back** — drafts in chat first, calls out any text it
   would overwrite that it didn't write, then on approval writes Abacus's three
   distinct fields (`description`, `plan`, `qa_plan`) rather than folding QA
   into the plan, since a story only reads as ready once both plans are set.

It grooms and stops. It never implements, never opens a branch, and never
creates, splits or moves tickets as a side effect — if the work is really
several tickets it recommends the split and leaves the call to you. When the
investigation shows the ticket shouldn't be done at all — already built, already
rejected, or solving a problem that no longer exists — that finding is the
deliverable instead of a dutiful plan.

**Prerequisites:**

- The **Abacus MCP server** connected to the session — this skill keys directly
  on `get_ticket` / `update_ticket` / `add_comment` and on Abacus's split of
  `description` and `plan` into separate fields. It is the plugin's one tracker
  dependency; without that server the skill has nothing to read or write.
- A checkout of the repo the ticket concerns, since step 2 is a real code pass —
  grooming from the ticket text alone is the failure mode the skill exists to
  prevent.
- Nothing else: no running stack, no `gh`, no gates. The deliverable is the
  ticket.

## `/colormath:refine-initiative` — design an initiative before it is built

Takes an initiative key (`/colormath:refine-initiative CM-00007`) and turns a
direction into something a team could build from, on the principle that an
initiative is *a direction, not a design* — a title, a handful of feature lines,
and none of the connective tissue that makes them buildable:

1. **Check it is an initiative, and check its status** — a plain ticket goes to
   `review-ticket` instead; an initiative that has already started **building**
   has its features locked by the server, so the skill says so up front rather
   than discovering it at the write step, and offers the description as the only
   thing it can still change.
2. **Read all of it** — description, every feature definition in order, every
   comment, and the tickets already filed under it (which only `get_ticket`
   returns).
3. **Investigate the architecture before asking anything** — the written
   decisions first (`AGENTS.md`, `docs/adr/`, rules files), then the code each
   feature lands in: does it already exist, which layer owns it, what it forces
   (a table, a migration, an event type, a deploy ordering), what it collides
   with, whether each feature is implementable as written, and what the feature
   list is *missing*.
4. **Interview until the picture is complete** — concrete multiple choice, up to
   four questions a round, three rounds usually plenty; a fourth round means it
   is designing the code (stop) or the initiative is really several (say so). It
   asks about the problem behind the title, what "done" looks like for the whole
   thing, the scope edges, the structural forks step 3 surfaced, and any
   architectural rule the work would need to bend.
5. **Rewrite at the right altitude** — the initiative's description carries the
   problem, the shape of the change, the real modules it lands in, the decisions
   taken and what they beat, the invariants it lives inside by ADR number, what
   is out of scope, and the surviving unknowns. Each feature is rewritten as a
   capability someone could take, with what it includes, what it does not, and
   the observable that means it works. The list is left in build order.
6. **Show, confirm, write back** — drafts everything in chat first, names what it
   would overwrite, then writes `update_ticket` (description only), then
   `update_feature` / `add_feature` / `move_feature`.

It **stops short of code**. No file-by-file steps, no signatures, no DDL, no test
lists — that is the ticket's altitude, and `/colormath:review-ticket` writes it
there later. It never bends an architectural rule silently: if the initiative
needs one to move, that is a question and then a line in the write-up. And it
**never starts building** — that transition is one-way, locks the features and
cuts a ticket per feature, so it is a person's decision and there is deliberately
no tool for it.

Two asymmetries it names rather than works around: there is **no delete tool**
for feature definitions, so a feature that should go is recommended for removal
and left to you in the web UI; and `update_feature` **replaces both fields**, so
it always sends the title.

**Prerequisites:**

- The **Abacus MCP server** connected, including the initiative tools
  (`get_ticket` returning `initiative_status` and `features`, plus `add_feature`
  / `update_feature` / `move_feature`).
- A checkout of the repo the initiative concerns, since step 3 is a real code and
  decision-record pass — refining from the initiative text alone is the failure
  mode the skill exists to prevent.
- Nothing else: no running stack, no `gh`, no gates.

## Adding a skill

One directory per skill: `skills/<name>/SKILL.md` with frontmatter
(`name`, `description`, optional `argument-hint` / `allowed-tools` / `model`).
The directory name is the command name (`/colormath:<name>`). Document the
skill in this README, keep it consumer-agnostic (no product names, no
hardcoded default branch), and note in the changelog which contract surfaces
it depends on — a rename of any of them must ship with the skill update in
the same release.
