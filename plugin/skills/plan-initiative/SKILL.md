---
name: plan-initiative
description: Plan every ticket in an initiative, one at a time and in build order, by running refine-ticket over each of them with the initiative's context injected — where this ticket sits in the sequence, what comes before and after it, and every decision already settled. Use this once an initiative has started building and its tickets exist, when someone wants the whole initiative planned, made ready, starred, or "taken from a list of titles to something the team can pick up". Finishes only when every plannable ticket in the initiative carries both an implementation plan and a QA plan.
argument-hint: [initiative key, e.g. CM-00007]
allowed-tools: Bash Read Grep Glob Skill AskUserQuestion mcp__abacus__get_ticket mcp__abacus__add_comment mcp__abacus__list_boards mcp__abacus__list_tickets
---

Plan every ticket under the initiative in "$ARGUMENTS", one at a time, until
the whole initiative is ready to pick up.

Each ticket is planned by `/colormath:refine-ticket`, which already knows how
to groom one. **This skill exists for what that one cannot see**: the ticket's
place in a sequence. Run seven times by hand, `refine-ticket` grooms seven
strangers — it re-derives the same background from scratch each time, asks the
same question seven times, and produces seven plans that each make locally
sensible choices that contradict each other at the seams. Run from here, each
ticket arrives knowing which initiative it belongs to, what was decided for the
tickets before it, and what is coming after it that it must not do twice.

So the loop is: **read the initiative once → plan each ticket in order,
carrying the context forward → verify → report.**

## 1. Read the initiative and check it can be planned

Call `mcp__abacus__get_ticket` on "$ARGUMENTS". It takes the key directly. If
that is a title fragment rather than a key, find it with `list_boards` then
`list_tickets` and confirm which one you landed on.

**Check `type` is `initiative`.** If it is an ordinary ticket, this is the wrong
skill — one ticket is `/colormath:refine-ticket`, and say so.

**Check it has tickets.** The children are in `get_ticket`'s response; the board
tools hide them. If there are none:

- `initiative_status` is `designing` — **the tickets have not been cut yet.**
  They are created when a human starts building, one per feature definition. Say
  that, point at `/colormath:refine-initiative` if the features themselves still
  need work, and stop. Do not start building to unblock yourself: it is one-way,
  it locks the feature list, and it is a person's decision.
- `building` with no children — somebody removed them, or the initiative was
  built with no features. Report it rather than guessing.

Then read the whole initiative: description, feature definitions, comments.
This is the context you will be injecting all the way down, so read it as the
thing that settles arguments — the decisions in it are **not up for
re-litigation** by the tickets underneath, and the injected context will say
so.

## 2. Establish the order, and show the run before you start

Sort the children by their position — that is build order, carried down from
the feature list the initiative argued about. Plan in that order. It matters
more than it looks: ticket 4's plan often depends on what ticket 2 decided, and
the whole point of this skill is that the earlier answer is available.

For each child, `get_ticket` it and note whether it is already planned. A
ticket is **planned when it carries both a `plan` and a `qa_plan`** — the pair
the tracker calls ready and stars in every list. Anything with only one of the
two is unfinished, not done.

Two kinds of child are **not plannable, and are not failures**:

- **tasks** — the type has no plan and no QA plan by design, and the tracker
  refuses to write one. Skip them, and say you skipped them.
- **initiatives** — nothing nests that deep here; report it as odd rather than
  recursing.

Now show the user the run before spending their attention on it: the
initiative, the ordered list, which are already planned, which are skippable,
and how many will therefore need grooming — **and that each one may ask them
questions**. A seven-ticket initiative is a long session, and someone who knows
that up front can say "just the first three today". Get a go-ahead. If they
want a subset, plan that subset in order and report the rest as untouched.

## 3. Plan each ticket, with its place in the sequence

For each ticket that needs it, in order, invoke `/colormath:refine-ticket` with
the key **first** — that is what it resolves on — followed by the context it
cannot get on its own. Keep the context compact and factual:

- **The initiative**: key, title, and a tight summary of what it is for and the
  decisions already settled in its description. Say explicitly that these are
  settled, so the sub-skill designs *within* them instead of reopening them.
- **Where this ticket sits**: "ticket 3 of 7", in build order.
- **What comes before**, by key and title, with a line on what each one's plan
  actually decided — not just its title. This is what stops seven plans
  contradicting each other, and it is only available because you are going in
  order.
- **What comes after**, by key and title, so the ticket does not absorb work
  belonging to a later one. Scope creep at the seams is the failure mode here.
- **The feature definition it came from**, if you can match it — the
  initiative's own words for this piece are usually sharper than the ticket
  title cut from them.

Then let `refine-ticket` do its job. Do not pre-empt it: no drafting the plan
yourself and asking it to rubber-stamp, no forbidding it from asking questions.
It investigates the code and interviews the user, and both are the point.

**Carry the answers forward.** When it finishes, note what was decided —
especially anything the user answered that will recur, and anything the plan
committed to that a later ticket must match. That note goes into the next
ticket's injected context. By ticket five you should be asking the user almost
nothing they have already told you, and if you are not, you are wasting their
time and should say so.

**Verify before moving on.** `get_ticket` the ticket again and confirm it now
carries both a `plan` and a `qa_plan`. If it does not — the user cut the
grooming short, or a question went unanswered — record it as unfinished and
move on rather than looping. Never report a ticket as planned because the
sub-skill ran; report it planned because the fields are there.

Tell the user where you are between tickets ("3 of 7 done, on CM-00014 next").
A long run with no narration reads as a hang.

## 4. Finish, and say what the state actually is

The skill is complete when **every plannable ticket in the initiative carries
both plans** — not when the loop has run.

Close with a list of every child: planned now, already planned before you
started, skipped as a task, or left unfinished with the reason. Then the things
that only became visible from up here:

- **Contradictions you had to reconcile** between tickets, and how.
- **Gaps** — work the tickets do not cover that the initiative implies. You
  cannot fix this: features are locked once building, and cutting new tickets by
  hand is not this skill's job. Name it, and let the user decide.
- **Tickets that should not exist** — already built, or duplicating another.
  Say so; deleting is theirs.
- **Open questions** that survived, per ticket.

Where the run produced a decision worth keeping at initiative level — a
rejected approach, a split, a sequencing constraint that emerged —
`add_comment` on the
**initiative** is its home, so the next person reading it finds the reasoning
without opening seven tickets.

## Rules

- **Build order, one at a time.** Never plan them in parallel or out of order:
  the whole value is that ticket N knows what N−1 decided.
- **Inject context every time.** A `refine-ticket` call from here that carries
  only a key has thrown away the reason this skill exists.
- **Don't do refine-ticket's job.** No drafting plans yourself, no suppressing
  its questions, no writing `plan` or `qa_plan` directly — this skill holds no
  `update_ticket` tool for exactly that reason.
- **Planned means both fields are set.** Verify by reading them back. The
  sub-skill returning is not evidence.
- **Never re-litigate the initiative.** Its description is settled context. If a
  ticket genuinely cannot be planned within it, stop and raise that — it is a
  finding about the initiative, not something to quietly design around.
- **Don't create, split, re-type or delete tickets**, and **don't start
  building** anything. This skill plans what exists.
- **Let the user stop.** Between tickets, not mid-grooming. A run they abandoned
  halfway is a normal outcome: report the half that landed.
