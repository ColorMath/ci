---
name: qa
description: Thoroughly QA a feature against the running platform — bring the stack up, find seeded accounts at every privilege tier, then probe correctness, security, and accessibility, proving each finding before reporting it. Produces a ranked findings list for the user to select from, fixes the selection, and hands off to ship. Use when asked to QA, test, audit, review, or go through a feature, find what's broken, or run a pre-release or pre-demo QA round.
compatibility: Requires shell and filesystem access, a locally runnable stack, optional browser automation for UI checks, and host-native invocation of the ship skill. Must support structured multi-selection or numbered chat fallback.
---

QA the focus area in the current user request against the **running** platform,
then fix
what the user picks and hand off to shipping.

The thing that makes this useful rather than theatre: a finding is a claim
about a running system, so it only counts once you've made the system
misbehave in front of you. Reading code tells you where to look; it does not
tell you what happens. Most of the value here comes from the gap between
those two.

If no focus area was given, ask for one before doing anything else — "QA the
platform" is unbounded and produces a shallow sweep of everything.

## 1. Scope the area

Map the focus area to concrete surfaces before touching anything: which
routes, services, jobs, templates, or tool definitions implement it, and which
of them a user or an API client can actually reach. Reachability is what
separates a real finding from a theoretical one.

Note the trust boundaries you cross — anywhere untrusted input arrives (a form,
an API argument, an uploaded file, an inbound email, a webhook) and anywhere
output is handed back to a browser. Those are where the interesting bugs live.

Read the repository's instruction files first. They carry the run commands,
ports, test invocations, and house rules, and they'll tell you which directories are
generated or vendored and therefore not yours to change.

## 2. Recon: get it running, get credentials

Read `references/recon.md`. Two things matter and both are easy to get wrong:
getting the stack up without disturbing the user's existing state, and getting
**several identities at different privilege tiers**. A single admin account
cannot find an authorization bug — the whole class only appears when you can
compare what different callers are allowed to do.

## 3. Probe

Read all three probe catalogs — `references/security.md`,
`references/correctness.md`, `references/accessibility.md` — and work through
the ones that apply to the surfaces you mapped. All three dimensions get
considered on every run; a feature that is correct and secure but unusable by
keyboard is not done.

Sweep first, fix nothing yet. Fixing while probing loses the thread and tempts
you to stop early, and the findings interact — knowing all of them usually
changes where the right fix goes. Today's most valuable finding may be the
third thing you notice while chasing the first.

**Build a small driver early.** Spend the first few minutes writing a helper
in your scratch directory that authenticates as any of your identities and
calls the surface — then every subsequent probe is one line instead of a
hand-assembled request. This pays for itself almost immediately: the
authorization matrix is dozens of calls, and a loop that prints
`allowed/denied` against `expected` turns it into a single readable table you
can paste into the report. Hand-running those calls is where QA sessions
quietly run out of budget and start sampling instead of covering.

**Side effects.** Treat local state as yours: write rows, upload files, create
and revoke credentials. Record a baseline first (row counts for the tables
you'll touch, the config you'll change) so you can put it back in step 7.

Stop and ask before anything that leaves the machine — email through a
configured provider, third-party API calls, webhooks, anything writing to a
shared or remote environment. A dev `.env` frequently holds a *live* provider
key, so "it's only the dev stack" is not a reason to assume mail won't
actually be delivered. Check where the provider points before you trigger a
send, and offer to redirect it locally instead.

## 4. Verify every finding

This step is what makes the report trustworthy, and it is the step most
worth slowing down for.

**Reproduce it against the running system** and keep the exact repro — the
request, the arguments, the observed response. If you cannot make it happen,
it does not go in the report.

**Report the mechanism you actually observed, not the one you assumed.**
Defenses you didn't check will surprise you, in both directions. A stored-XSS
payload that "obviously" executes may be stopped by a CSP nonce — while the
real bypass turns out to be a CDN the CSP allowlists, which you'd only find by
loading the page in a browser and looking. Had you reported the assumed
mechanism you'd have been wrong twice: wrong that it worked, and wrong about
why. Chase the finding until you can state the actual chain.

**Establish whether it's pre-existing.** Before attributing anything to recent
work, check it against a clean tree (`git stash -u`, re-run, restore) or
against the base branch. This applies to failing tests and lint errors too:
`make preflight` mirrors the colormath gates locally, but local tool versions
drift from CI, so a gate that fails locally and passes in CI is an environment
artifact, not a finding. When they disagree, CI is the authority — say so
rather than "fixing" a phantom.

**Ask what else shares the shape.** A bug found in one place is a probe you
now know works; run it against the sibling surfaces. One unvalidated caller
usually means several.

## 5. Report and let the user choose

Present findings ranked by severity, worst first. For each one:

- **What breaks**, in one line — the defect, not the code smell.
- **Blast radius** — who can trigger it, what they need, what they get. "Any
  editor" and "any unauthenticated sender" are very different findings even
  with identical code.
- **The repro** you ran, and what you observed.
- **The fix you'd make**, and anything about it that needs the user's call.

Say plainly what you verified versus what you inferred, and mention what you
*didn't* cover — an area you couldn't reach, a path that needed credentials
you didn't have. A QA report that hides its gaps invites false confidence.

Also report what you tried that came back **clean**. "Authorization held on
all 19 cross-tenant cases" is a real result and tells the user where not to
spend their next hour.

Then use the host's structured multi-selection mechanism when available to let
them pick what to fix. Otherwise, present a numbered list and accept a
comma-separated selection in chat. Include severity in each option so the
choice is informed. If a finding needs a design
decision rather than a fix — two systems disagreeing, a deliberate tradeoff —
surface the decision instead of silently choosing for them.

## 6. Fix what they picked

Work through the selected findings, matching the surrounding code's idiom.

Then **re-run the original repro against the running system**. Unit tests
passing is not the same as the bug being gone: a fix can be correct in
isolation and still miss a second code path that reaches the same place, and
that failure mode looks exactly like success from the test suite. Re-running
the thing that broke is the only check that actually closes the loop.

Add regression tests at the layer the bug lived at, and run the repo's full
suite plus `make preflight` (per the repository's instruction files, once,
before opening a PR).
Distinguish any failure you introduced from the pre-existing ones you
catalogued in step 4.

## 7. Restore, then ship

Undo what you did to the environment: delete the rows and files you created,
revoke credentials you minted, restore any config you changed, and confirm the
baseline from step 3 matches. QA that leaves debris behind poisons the next
person's run — and if you flipped a provider or a feature flag, leaving it
flipped is its own outage waiting to happen.

Show the user the restored state, then invoke the `ship` skill through the
host's native skill mechanism to open the PR, watch the gates, and triage
review. Shipping stops at a
merge recommendation; merging stays the user's decision.

If the user declined every finding, don't ship — summarize and stop.

## Judgement

**Depth beats breadth.** Six proven findings in one flow are worth more than
forty suspicions across ten. The user has to act on these; each unverified
item spends their attention.

**Silent wrongness outranks loud failure.** An endpoint that errors gets
noticed. An endpoint that cheerfully returns the wrong answer — an empty list
where the UI shows twenty rows — can sit there for months. When you find two
surfaces reading the same data, make them agree before you move on.

**Follow the surprise.** When something behaves unexpectedly, even trivially,
that is the highest-information moment in the run. The scorecard that returns
nothing, the error message naming a table you didn't expect — chase it.

**Stay inside the mandate.** You're testing the user's own platform on their
instruction. Probe it hard. Don't reach for third-party systems, other
people's data, or production, and don't leave a hole open to demonstrate a
point — if you plant a payload to prove an XSS, remove it in step 7.
