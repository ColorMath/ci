---
name: refine-ticket
description: Turn a thin ticket into one that can actually be worked — read it, investigate the code it touches, ask the few questions whose answers change the outcome, then write back a clear description, a file-anchored implementation plan, and an executable QA plan. Use this whenever someone wants a ticket groomed, refined, fleshed out, scoped, estimated, made ready, or "looked at properly" — or names a ticket key (CM-00001) and asks what it would take. Not for finding unknown problems in a feature (that's /colormath:qa), not for a reported defect you intend to fix now (that's /colormath:bugfix), and not for implementing the ticket — the groomed ticket is the deliverable.
argument-hint: [ticket key, e.g. CM-00001 — or enough of the title to find it]
allowed-tools: Bash Read Grep Glob AskUserQuestion mcp__abacus__get_ticket mcp__abacus__update_ticket mcp__abacus__add_comment mcp__abacus__list_boards mcp__abacus__list_tickets mcp__abacus__list_members
---

Groom the ticket named in "$ARGUMENTS" until someone else could pick it up cold
and work it.

A ticket is **a reminder, not a specification**. It was written by someone who
had the whole context in their head and wrote down only the trigger — a title,
maybe a sentence. Everything that made it obvious to them at the time is
missing, including, often, the reason it matters.

That shape invites two failure modes, and this skill exists to prevent both.
The first is **fluent restatement**: expanding the title into three paragraphs
of confident prose that add words and no information, then a plan of generic
steps ("update the relevant service", "add tests") that name nothing and could
have been written without opening the repo. It reads like grooming and is worth
nothing, because no assumption in it was ever checked. The second is
**interrogation**: dumping a dozen open-ended questions on the person who filed
it, which is slower for them than writing the ticket properly themselves.

The cure for both is the same and it is the spine of this skill:
**read → investigate → ask → draft → confirm → write.** Investigate *before*
you ask, so your questions are concrete and few. Anchor every plan step in a
real file, so the plan can be wrong in a way someone can catch.

Quote the ticket by its **key** (`CM-00001`) throughout — that's what people
call it by, never the UUID.

## 1. Read the ticket and everything attached to it

Call `mcp__abacus__get_ticket`. It takes the key directly, and case and
zero-padding don't matter, so `cm-1` resolves. If "$ARGUMENTS" is a title
fragment rather than a key, find it with `list_boards` then `list_tickets` and
confirm which one you landed on before doing anything else.

Read all of it: description, existing plan, existing QA plan, **every
comment**, type, swimlane, assignee, and whether it sits under a project. Comments are where decisions
already made go to hide — grooming a ticket into a plan that contradicts a
decision recorded in its own comment thread is an avoidable embarrassment. If
the ticket *is* a project, `get_ticket` is the only place its contents are
listed; the board tools hide them.

If it already has a description or plan, you are **revising, not authoring**.
Read the prior text as evidence of intent, keep what's still true, and note
anything you're contradicting so you can raise it rather than quietly deleting
someone's thinking.

## 2. Investigate the code before you ask anything

This is the step that separates a groomed ticket from a padded one, and it is
where most of the time should go.

Go find the thing the ticket is talking about. Read the routes, services,
models, templates, jobs and config it would touch. You are answering, for
yourself, questions the filer shouldn't have to:

- **Does it already exist?** Partially built, built and disabled behind a flag,
  or built and then deliberately removed. Check the repo's architecture notes
  and decision records — a ticket asking for something a written decision
  explicitly rejected is the single most valuable thing to catch, and you catch
  it here or not at all.
- **Which files actually change**, and roughly how much. Name them.
- **Is the ticket's own wording precise?** Titles carry typos, ambiguous nouns
  and stale names. Resolve them against the code, and where you can't, they
  become questions in step 3 rather than assumptions in step 5.
- **Is this one ticket or several?** If the work has genuinely independent
  halves, say so in the plan and let the user decide — don't silently groom
  three tickets' worth of work into one.

Then hunt specifically for **what makes it non-trivial**. A ticket whose code
change looks like a one-line edit is a signal to keep digging, not a conclusion:
the real work is often entirely outside the diff — a DNS record, a vendor
account or verified identity, a migration that has to land in a particular
order, a credential someone has to issue, a deploy that must reach two services
and not one. Miss that and the plan is a confident lie about the effort, and
whoever picks the ticket up discovers it at the worst moment. Look for
prerequisites, ordering constraints, and anything the repo can't do to itself.

Distinguish, out loud and in the final write-up, **what you verified** from
**what you inferred**.

## 3. Ask only the questions whose answers change the outcome

Because you did step 2, you can now ask concrete multiple choice instead of an
open survey — "should the staging sender use the same domain, or its own?"
rather than "any thoughts on email?". Concrete options cost the user seconds,
and they surface possibilities they hadn't considered. That's what
`AskUserQuestion`'s option lists are for; put your recommendation first and say
so.

**Batch them into one round**, not a trickle across several turns. Where the
answers are genuinely dependent — the second question only makes sense given
the first — a second round is fine, but two is the ceiling. Grooming that costs
more of the user's attention than the work itself has failed at its job.

The unknowns that most often decide whether a plan is right:

- **Why now, and why at all.** The ticket says *what*; it rarely says what
  problem the person hit. The obvious implementation frequently satisfies the
  title while missing the reason it was filed.
- **What "done" looks like** — the observable that flips it. If you can't name
  one, you don't yet understand the ticket.
- **The scope edges.** What's deliberately *out*. Adjacent, tempting, related
  work is exactly what turns a two-file change into a fortnight.
- **User-visible forks.** Anywhere two reasonable implementations differ in a
  way someone would notice: copy, defaults, what happens to users mid-flow, what
  happens to data already written under the old behavior.
- **The ambiguities step 2 couldn't settle** — a typo'd value, a name that maps
  to two things, a threshold nobody wrote down.
- **Constraints outside the code** — a date, a dependency on another ticket, a
  person who has to do something first.

**If you would do the same thing either way, don't ask.** Where a conventional
default exists, take it and write the assumption into the ticket where it can be
contradicted — that's cheaper for everyone than a question. If the ticket is
already specific enough to plan from, skip this step and say so.

Then actually **let the answers move you**. Asking and then writing the plan you
had already decided on is worse than not asking.

## 4. Write a description that stands on its own

Written for someone with **none** of the context — the filer in six months, or
whoever picks it up. It describes the *problem*, not your solution:

- **Context** — what's true today, and what's wrong or missing about it.
- **Why it matters** — who is affected and what it costs them. A ticket without
  this gets deprioritized forever, correctly.
- **Acceptance criteria** — the heart of it. Observable statements a third
  person could check without asking you. "Emails send correctly" is not one;
  "a password-reset email arrives with `From: noreply@…` and passes DKIM" is.
- **Out of scope** — the adjacent work this ticket is deliberately not doing,
  and where it went instead.

Never delete a stated constraint just because it's inconvenient to plan around.

## 5. Write an implementation plan someone could follow

Ordered steps, each naming **real paths** — `services/billing.py:212`, not "the
billing service". A step that names no file is a wish, and the reader can't tell
a wrong plan from a vague one.

Lead with **prerequisites and blockers** when there are any, because they decide
whether the work can start at all, and they're what step 2 was hunting for.

Then, for the change itself: the files and the order, the *layer* the change
belongs at and why there rather than the place the symptom appears, any
migration or data implication, and the rollout sequence when deploy order
matters. Include **what explicitly does not need to change** — it bounds the
diff against scope creep, and it's the visible proof that you actually looked.

Close with **open questions** — everything unresolved, stated plainly rather
than papered over. A ticket that admits two unknowns is more useful than one
that silently guesses at them. Anything you assumed in step 3 goes here too, as
an assumption, so it can be contradicted cheaply.

Size it honestly. If the work turned out to be bigger than the ticket implies,
say so here rather than letting someone discover it mid-implementation.

## 6. Write a QA plan that someone can actually execute

This is the section most tickets never get, and the reason defects ship. The
test is mechanical: **could a person execute each item without asking you what
you meant?** Each needs a surface, an identity, an input, and an expected
observable. "Verify it works" fails that test.

Work these dimensions and drop the ones that don't apply, rather than padding:

- **The happy path**, at the privilege tier that actually matters.
- **Authorization and tenancy** — the wrong role, the neighboring tenant, the
  logged-out visitor. One admin account proves nothing about access control.
- **The failure and edge cases this change introduces** — bad input, absent
  optional data, the boundary values, the second concurrent attempt.
- **Regression surface** — what *else* reaches this code. Step 2 found the other
  callers; this is where they get checked.
- **Data written under the old behavior.** Existing rows rarely match what the
  new code assumes, and local seed data is pristine and therefore hides it.
- **Accessibility**, when there's UI: keyboard reachability, labels and
  semantics, announcement of state changes, contrast.
- **Post-deploy verification**, when the change only manifests in a deployed
  environment — name the environment, the check, and who can run it.

Then separate **what automated tests will cover** from **what needs hands**, and
name the repo's gates the change implicates — diff coverage on new logic, a11y
on templates, a dependency or secrets scan on new config. A QA plan that
duplicates the test suite wastes the tester; one that assumes the suite covers
the interesting case wastes the release.

## 7. Show it, confirm, then write it back

Show the drafted description and plan in chat **before** writing anything, and
ask for a go-ahead. Grooming is a proposal about someone else's intent, and
they get to correct it while it's still cheap.

Call out explicitly, at that moment, if you are **overwriting description or
plan text you didn't write** — say what's being replaced so the loss is a
decision rather than an accident.

On approval, `mcp__abacus__update_ticket` with **three separate fields**:
`description`, `plan` (the implementation plan), and `qa_plan`. They are
distinct fields, not sections of one — a story is shown as ready only once it
has both `plan` and `qa_plan`, so folding QA into the plan field leaves the
ticket looking unready no matter how good the writing is. All three are
markdown, stored and shown verbatim. Pass only the fields you're changing;
anything you omit keeps its current value. Where the grooming produced a decision worth
preserving as a record — a rejected approach, the reasoning behind a scope cut —
`add_comment` is the right home for it, since the plan should read as the
current intent rather than its history.

Finish by telling the user, in chat: the ticket key, what changed, what you
verified against the code versus assumed, and the open questions that survived.
Nothing here can delete a ticket — say so plainly if you're asked to.

## Rules

- **Investigate before you ask.** Questions from a cold read are a survey;
  questions after a code pass are a decision. Never open with the question round.
- **Every plan step names a real file.** No step that could have been written
  without opening the repo.
- **Ask only what changes the outcome**, in one batch, two rounds at the
  absolute most.
- **Never invent an answer the user didn't give.** Unresolved goes into the
  ticket as a stated open question or a stated assumption — visibly, where it
  can be contradicted — never silently resolved in your favor.
- **Don't implement the ticket.** No branches, no code edits, no PRs. The
  groomed ticket is the deliverable; `/colormath:bugfix` and `/colormath:ship`
  take it from there as separate, deliberate acts.
- **Groom this ticket only.** Don't create, split, move, reassign or re-type
  tickets as a side effect — if the work is really several tickets, recommend
  the split and let the user call it.
- **Confirm before writing**, and never overwrite someone else's description or
  plan without saying that's what you're doing.
- **Say when a ticket shouldn't be done.** If the investigation shows it's
  already built, already rejected by a recorded decision, or solves a problem
  that no longer exists, that finding *is* the deliverable — report it instead
  of dutifully producing a plan for work nobody needs.
