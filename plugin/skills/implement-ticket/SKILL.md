---
name: implement-ticket
description: Take a planned ticket all the way to a shipped PR — check its plan against current code, ask only what blocks, build at the planned layer, execute its QA plan against the running stack, then hand off to the ship skill. Use when asked to implement or work a ticket that has already been groomed. Not for grooming (use refine-ticket) or a defect report (use bugfix).
compatibility: Requires shell and filesystem access, git, a locally runnable stack, host-native invocation of qa and ship, and Abacus MCP get_ticket, add_comment, list_boards, and list_tickets.
---

Implement the ticket named in the current user request, QA it, and ship it.

The ticket has already been groomed — the `refine-ticket` skill wrote a
description, an implementation plan whose steps name real files, and a QA plan
someone could execute. **Your job is to execute that, not to redo it.** The
thinking happened; this is where it meets the code.

The one thing that makes this more than typing: **the plan was written against
the codebase as it was.** Between grooming and now, files moved, an adjacent
change landed, an assumption expired. A plan executed blindly produces a diff
that satisfies the letter of a document and breaks the thing it was for. So the
first act here is checking the plan still describes reality, and the most
valuable outcome is sometimes "this plan no longer holds, here's why" rather
than a PR.

## 1. Read the ticket and check it is ready to build

Call Abacus MCP `get_ticket`. It takes the key directly; case and padding
don't matter. If the current request contains a title fragment, resolve it with
Abacus MCP `list_boards` and `list_tickets`, then confirm which ticket you
landed on.

Read all of it — description, **implementation plan**, **QA plan**, every
comment, type, and the initiative it belongs to if it has one. Comments carry
decisions made after the plan was written, and they win.

Then check it can be implemented at all:

- **No implementation plan** — stop. This skill executes a plan; it does not
  write one. Invoke or recommend the `refine-ticket` skill with the key and say
  why: a plan written by the run that implements it has never been read by
  anyone.
- **No QA plan** — say so and ask whether to continue. You can implement without
  one, but nothing will check the result the way a groomed ticket intends, and
  the honest thing is to let them choose rather than inventing acceptance
  criteria at the moment they'd be most convenient.
- **A task** — that type carries no plans by design. It is not code work; it is
  a chore somebody does. Say so and stop.
- **An initiative** — the wrong altitude. Its tickets are what get implemented;
  the `plan-initiative` skill plans them, then this skill takes them one at a
  time.

If the ticket belongs to an initiative, read that too. The initiative says what
the whole thing is for and what the neighbouring tickets are doing, which is how
you avoid building something that collides with the ticket after it.

## 2. Check the plan against the code before you touch anything

Walk the plan step by step with the repo open. For each step:

- **Does the file still exist, at that path?** A renamed module means the plan
  is describing a codebase that no longer exists.
- **Does the surrounding code still look like the plan assumes?** The function
  it says to extend, the layer it says to add to, the caller it says will pick
  the change up.
- **Has any of it already been done?** By the ticket next to it in the
  initiative, or by an unrelated PR that passed through.
- **Do the repo's conventions still allow it?** Read the repository instruction
  files, ADRs, and rules files. A plan that was fine in March can violate a
  decision recorded in April, and the decision wins.

Where the plan holds, say so briefly and move on. Where it does not, that is a
**finding**, and it goes to the user in step 3 rather than being quietly
routed around. Silently improving a plan is how a reviewed decision gets
replaced by an unreviewed one.

## 3. Ask only what actually blocks you

By this point there usually is nothing to ask — grooming's whole job was to
remove these, and a skill that reopens settled questions has wasted the
grooming. Ask only when you genuinely cannot proceed:

- the plan no longer matches the code and there is a real choice about what to
  do instead;
- two readings of a step produce materially different, user-visible results;
- the plan needs something the repo cannot give itself — a credential, a vendor
  account, a decision that belongs to someone else.

Use one round through the host's structured question mechanism when available,
with concrete options and the recommendation first. Otherwise ask the same
numbered options in chat. Anything
you can settle from the ticket, the initiative, the ADRs or the conventions is
not a question. And if you find yourself wanting several rounds, the ticket is
not groomed and should go back to `refine-ticket` — say that instead
of interviewing your way to a design.

## 4. Build it, at the layer the plan names

Branch first — `feat/<ticket-key-slug>` or the repo's own convention — never the
default branch.

Then implement, in the idiom of the surrounding code: its conventions, its
layering, its naming, its comment density. Follow the plan's ordering when it
has one; it usually encodes a dependency.

Three things worth more than speed:

- **Tests at the layer the change lives at**, not one layer up where they are
  easier to write. Where the plan or the repo names a coverage or gate
  expectation, meet it here rather than discovering it in CI.
- **Deviations get recorded, not hidden.** If implementing shows the plan was
  wrong — a step that cannot work, a better layer, a case the plan missed —
  say so in chat as you go, and put it in the PR body and in a ticket comment
  at the end. The plan stays as the record of what was intended; the comment
  records what actually happened and why. Never rewrite the plan field to match
  what you did: that erases the difference between the two, which is the only
  interesting part.
- **Scope discipline.** Build the ticket, not the ticket plus the thing next to
  it that is obviously also wrong. Note the neighbour, finish the ticket. If it
  belongs to an initiative, the neighbour may literally be the next ticket.

## 5. Execute the QA plan against the running stack

The QA plan is a list of claims about a running system, and an item counts only
when you have watched the system agree. A passing test suite is not the QA plan
— it is one of the things the QA plan usually says to check.

Bring the stack up the way the repo does it (`make up-dev` or its equivalent),
and follow the `qa` skill's recon discipline for identities and seeded data —
authorization items need the *wrong* role as well as the right one, and one
admin account proves nothing about access control.

Work every item and record what you observed: the request and response, the row
you read back, the screen state. Drive UI items through a browser if one is
reachable; if none is, mark them `⚠️` unverified and say so plainly rather than
inferring them from the code you just wrote — which is the least trustworthy
possible source for whether the UI works.

Anything that fails is yours to fix now, then re-run the item. A QA plan item
that fails and gets shipped anyway is worse than one nobody ran, because the
document now says it passed.

Restore what you mutated: rows you created, config you flipped, credentials you
minted. Local state is yours to change and yours to put back.

## 6. Ship it

Run the repo's full local gate mirror once (`make preflight`) so an avoidable
failure does not cost a CI round trip. Then invoke the `ship` skill through the
host's native skill mechanism, which
takes it the rest of the way: PR, gates, the review, a second pass over this
same QA plan against the running stack, fixes for what turns up, and either an
auto-merge when the PR is genuinely clean or a hold with the reason.

Give ship a title naming the change in the ticket's own terms, and a body that
carries what a reviewer cannot reconstruct: **the ticket key and what it asked
for**, **where the plan held and where it did not**, **the QA plan's results
including anything unverified**, and any deviation you made and why.

When ship comes back, call Abacus MCP `add_comment` on the ticket with the
outcome — the PR
link, whether it merged or is held, and the deviations. That comment is how the
ticket stops being a plan and becomes a record. Leave the ticket's own fields
alone: `plan` and `qa_plan` are what was intended, and the comment is what
happened.

Do not move the ticket between lanes. Lane meaning is per board — one team's
"In Review" is another's "Staging" — and guessing at somebody's workflow is
worse than leaving it where they put it. Say what you would have moved it to, if
it seems useful, and let them.

## Rules

- **Execute the plan; don't rewrite it.** No re-grooming, no "improving" the
  plan silently. Where it is wrong, say so and decide with the user.
- **A ticket with no plan goes back to `refine-ticket`.** Writing the
  plan and implementing it in the same breath means nobody ever reviewed the
  plan.
- **Never work on the default branch**, and never merge by hand — `ship` owns
  that decision and has the gates to make it.
- **QA is executed, not asserted.** Every item gets an observation. Unverified
  is a legitimate result and gets marked; assumed is not.
- **One ticket.** Don't implement its neighbours, don't fix adjacent bugs beyond
  what the change requires, don't create tickets. Note them and move on.
- **Record what actually happened** in a ticket comment at the end,
  deviations included, and leave the planned fields as the record of intent.
