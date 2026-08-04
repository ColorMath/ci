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
2. **Stamp both refs** to the tag you are about to cut:
   - the `colormath-ref` input default in `.github/workflows/gates.yml` — how
     the workflow fetches its own matching scripts/actions in consumer repos;
   - `COLORMATH_REF` in `Makefile.colormath` — how the *local* mirror fetches
     those same scripts, so `make preflight` runs what CI runs.

   They must match, and CI's `refs-lockstep` job fails the PR when they don't.
   Miss the second and preflight silently runs an older gate script than CI —
   invisible until a script changes between the two tags.
3. Update `CHANGELOG.md` (with Upgrade notes if MAJOR).
4. Tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.
5. **Canary**: bump talas first (PR with the new `@vX.Y.Z`), merge when its
   gates are green, let one staging deploy soak.
6. Then intendent, then runwayz — runwayz always last (furthest from the
   template; its bump PRs are where weird interactions surface, and by then
   the release is proven).

This is a checklist habit, not machinery. The automated bump workflow
(`colormath-bump.yml` in each consumer) arrives with the Copier channel.

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
