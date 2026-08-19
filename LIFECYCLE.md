# colormath lifecycle

The law for how colormath versions, releases, and propagates. The failure mode
this design exists to prevent: updates become annoying → consumer vendors or
forks → permanent drift (the portico story).

## Versioning

One SemVer tag stream (`vX.Y.Z`) covering every artifact class, one
CHANGELOG. Consumers pin **exact tags everywhere** — reusable-workflow `@refs`,
terraform `?ref=`, copier `_commit`. No floating `v1` tag: an upgrade must
only ever arrive as a dedicated PR whose diff and changelog explain
themselves, validated by the consumer's own gates.

**The MAJOR rule:** if a consumer's CI, deploy, or `terraform plan` can change
from green/no-op to red/diff *without the consumer editing anything*, the
release is MAJOR.

- **MAJOR**: a gate becomes required or stricter; Python default bumped; a
  workflow input/secret renamed; a terraform variable/output renamed or a
  default changed in a way that alters infrastructure; a Makefile target
  renamed; a copier question renamed/removed.
- **MINOR**: a new gate shipped **opt-in or warn-only**; a new input/variable
  with a safe default; a new copier-managed file; a new plugin skill.
- **PATCH**: keeps green things green — bug fixes, action-version bumps inside
  the workflow, comment/doc changes.

**New-gate rollout:** ship the gate in a MINOR with `enable-<gate>: false` as
the default (or `continue-on-error`), promote it to default-on in the next
MAJOR. Consumers take MINORs for free; the MAJOR's upgrade notes say "fix the
findings or set `enable-<gate>: false` and file yourself an issue."

Every MAJOR changelog entry must include an **Upgrade notes** block written as
a prompt you can paste into Claude Code in each consumer repo ("rename input X
to Y, run `make preflight`, fix any a11y findings in templates/").

While on `0.x`: breaking changes may land in any release; pins become
contractual at `v1.0.0`.

## Releasing

1. Land the change on `main` via PR — colormath's own CI (the gate suite
   running against `example/`) must be green. If the change touches the gates'
   behavior, `example/` must be updated in the same PR to keep it passing.
   Write the release notes under `## Unreleased` in `CHANGELOG.md` as you go
   (with Upgrade notes if MAJOR). **Never stamp a version by hand.**
2. Cut it: run the **Release** workflow with the version, or locally
   `./release/cut.sh vX.Y.Z` (`--dry-run` first to see the diff). That stamps
   every version site, dates the changelog section, commits, creates an
   annotated tag, pushes both atomically, and publishes the GitHub Release.
3. **Canary**: bump talas first (PR with the new `@vX.Y.Z`), merge when its
   gates are green, let one staging deploy soak.
4. Then intendent, then runwayz — runwayz always last (furthest from the
   template; its bump PRs are where weird interactions surface, and by then
   the release is proven).

Steps 3–4 stay human. Everything before them is machinery, because the
checklist that used to cover them had the steps written down and they were
still missed. The automated bump workflow (`colormath-bump.yml` in each
consumer) arrives with the Copier channel.

### The invariant

> On `main`, at every commit: every version this repo writes down — including
> both host plugin manifests — agrees, equals the newest tag reachable from
> `HEAD`, and that tag exists.

Consumers pin exact tags, and the stamps are how colormath fetches its own
scripts at that pin. Break the invariant in one direction — a stamp naming a
tag that does not exist yet — and every consumer's `make preflight` 404s on
every gate script. Break it in the other — a stamp naming an older tag — and CI
and the local mirror silently run different gate scripts, wrong only once a
script changes between the two. Both have happened here. Nine of the sixteen
tags up to `v3.0.0` are internally inconsistent (`release/verify.sh
--audit-all` prints the table).

The cause was stamping *forward*: writing the next version into the tree days
before the tag existed, leaving a window that closed only if someone
remembered. So **stamps move only in the release commit**, which is tagged with
the version it stamps in a single `git push --atomic` — git updates both refs
or neither. There is no window to forget about, and the invariant is therefore
true continuously, including on the release commit itself.

The same verifier also checks that both plugin manifests expose the one
canonical `plugin/skills/` tree, that all seven skills remain portable Agent
Skills, and that the reference `skills-ref` validator passes when installed.

That is what makes `release-consistency` safe to run as a blocking check in CI,
despite the warning under [Drift detection](#drift-detection-steady-state)
below: it can only fail on a PR that edited a version string. A PR that touches
none of them inherits main's consistent state and passes unconditionally, so it
can never stand between a hotfix and `main`.

Documentation examples are deliberately **not** stamped — they read `@vX.Y.Z`
and point at `/releases/latest`. Nine of them had rotted to versions one to
three majors stale. Deleting the data beat automating it.

### When a release goes wrong

Re-running is always safe. `cut.sh` refuses to start from an inconsistent tree,
rolls back its own commit and tag if the atomic push is rejected, and resumes at
the publish step if the tag landed but the GitHub Release did not.

**Never move or delete a published tag.** Not `git tag -f`, not delete-and-
recreate. A consumer that already fetched it gets `would clobber existing tag`
on their next fetch, and cached CI runners go nondeterministic — this repo
exists to not do that to consumers. If a release is wrong, burn the version:
cut the next one immediately and edit the bad Release's body to lead with
**WITHDRAWN — use vX.Y.Z+1**. That costs one integer and stays honest.

Tags at and below `v3.0.0` are a mix of lightweight and annotated, and several
are internally inconsistent. Both are historical artifacts, left alone on
purpose. Every tag from `v3.1.0` on is annotated and verified before it exists.

## Propagation (steady state, once Copier lands)

Each consumer carries a copier-managed `colormath-bump.yml`: weekly cron +
manual dispatch. It bumps workflow `@refs` and terraform `?ref=`s, runs
`copier update --conflict rej` (its own check fails if any `.rej` files
remain), and opens **one PR per release** titled "colormath vA → vB" with the
changelog excerpt. Conflicts are resolved in that PR branch, in the consumer
repo, with Claude Code — never anywhere else.

**The parameterize trigger:** if the same file conflicts on two consecutive
bumps, stop hand-patching — add a copier variable or workflow input to
colormath. Sanctioned permanent divergence goes on the copier exclude list and
shows up in the weekly drift report forever: visible decision, not silent rot.

## Drift detection (steady state)

A weekly workflow per consumer updates one "colormath drift report" GitHub
issue: (1) hand-edits to managed files, (2) intentionally ejected files,
(3) staleness vs the latest tag. **Advisory only, never merge-blocking** — a
hotfix blocked by a drift gate gets the gate disabled, and that's the
beginning of the end.

## Testing colormath itself

- `example/` is a minimal compliant consumer; every PR runs the full gate
  suite against it (`.github/workflows/ci.yml`, with `colormath-ref` set to
  the PR SHA so the change under test is what runs).
- The gitleaks gate scans colormath's own history on every PR — this repo is
  public; keep every example value obviously fake.
- Real-world validation is the talas canary in the release checklist — no
  consumer testing happens from colormath's side.
