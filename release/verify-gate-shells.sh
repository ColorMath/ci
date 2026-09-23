#!/usr/bin/env bash
#
# Every gate job must name `shell: bash`.
#
# This exists because the bug it catches is invisible: when it is wrong, the
# gates do not fail loudly — they *pass*, every time, whatever the tool found.
# There is no red build to investigate, so nothing but a structural check finds
# it.
#
# The mechanism, in full. Gate steps are written
# `gate-cmd 2>&1 | tee /tmp/x.log` so the gate-summary step can read the output
# back. GitHub's implicit shell for a `run:` step is `bash -e {0}`, which has no
# `pipefail`, and a pipeline's exit status is its *last* command's — tee's,
# which is 0 whatever the gate did. Naming the shell explicitly gets
# `bash --noprofile --norc -eo pipefail {0}` and the gate's own exit code
# reaches the step.
#
# gates.yml declared `shell: bash` once at the workflow level and every job then
# set a job-level `defaults.run.working-directory`. A job-level `defaults.run`
# REPLACES the workflow-level one rather than merging with it per key, so all
# but one job silently reverted to the implicit shell. It shipped that way in
# v3.0.0, v3.1.0 and v4.x: a consumer's run printed `1 failed, 4424 passed` from
# pytest and `1 problem (1 error)` from html-validate, and reported both gates
# green.
#
# A comment saying "do not remove this" was already there, and was not enough —
# nobody removed it, they added a sibling key three lines below it. Hence a
# check rather than more prose.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$root" <<'PY'
import sys, pathlib, yaml

root = pathlib.Path(sys.argv[1])
failures = []
checked = 0

for path in sorted((root / ".github" / "workflows").glob("*.yml")):
    doc = yaml.safe_load(path.read_text())
    if not isinstance(doc, dict):
        continue
    workflow_shell = ((doc.get("defaults") or {}).get("run") or {}).get("shell")
    for name, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        steps = job.get("steps") or []
        # Only `run:` steps are at risk; a job of nothing but `uses:` has no
        # shell to get wrong.
        if not any(isinstance(s, dict) and "run" in s for s in steps):
            continue
        checked += 1
        job_run = (job.get("defaults") or {}).get("run")
        if job_run is None:
            effective = workflow_shell
            where = "workflow-level default"
        else:
            effective = job_run.get("shell")
            where = "job-level defaults.run (which REPLACES the workflow one)"
        if effective != "bash":
            failures.append(
                f"{path.name}::{name} — effective shell is "
                f"{effective!r}, from {where}. Without `shell: bash` the step "
                f"runs under `bash -e {{0}}` with no pipefail, and every "
                f"`| tee` pipeline reports success."
            )

if failures:
    print("Gate jobs whose `run:` steps would lose pipefail:\n")
    for f in failures:
        print(f"  ✗ {f}")
    print(
        "\nFix: give that job's `defaults.run` a `shell: bash` beside its "
        "`working-directory`."
    )
    sys.exit(1)

print(f"OK — all {checked} job(s) with `run:` steps resolve to `shell: bash`.")
PY
