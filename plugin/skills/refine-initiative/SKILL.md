---
name: refine-initiative
description: Turn a thin initiative into one a team could build from — read it and its feature definitions, investigate the architecture it lands in, interview the person who filed it until the picture is complete, then rewrite the initiative and every feature with the background and structure implementation needs. Use this whenever someone wants an initiative refined, fleshed out, scoped, designed, "made real", or checked before it starts building — or names an initiative and asks what it would actually take. Stops short of code-level plans — those belong on the tickets (/colormath:refine-ticket), and this is the layer above.
argument-hint: [initiative key, e.g. CM-00007 — or enough of the title to find it]
allowed-tools: Bash Read Grep Glob AskUserQuestion mcp__abacus__get_ticket mcp__abacus__update_ticket mcp__abacus__add_comment mcp__abacus__add_feature mcp__abacus__update_feature mcp__abacus__move_feature mcp__abacus__list_boards mcp__abacus__list_tickets
---

Refine the initiative named in "$ARGUMENTS" until the team could start building
from it without coming back to ask what it meant.

An initiative is **a direction, not a design**. Someone had a shape in their
head, wrote down a title and a handful of feature lines, and stopped — because
at the moment of writing, the connective tissue was obvious to them. What is
missing is everything that makes it buildable: which parts of the system it
lands in, what already exists, which architectural decisions it has to live
with, what it deliberately will not do, and whether those feature lines
describe anything a person could actually pick up.

Two failure modes follow from that shape, and this skill exists to prevent
both. The first is **the confident restatement** — expanding four feature
lines into four paragraphs of fluent prose that add words and no information,
none of it checked against the codebase. The second is **designing the code** —
sliding down into file-by-file steps, function signatures, and schema DDL. That
is a different job at a different altitude, done per ticket, later, by
`/colormath:refine-ticket`. This skill's altitude is: *what is being built, in
what shape, against what that already exists, and does it hold together.*

The spine is **read → investigate → interview → draft → confirm → write**.
Investigate before interviewing, so the questions are concrete and few per
round. Refer to the initiative by its **key** (`CM-00007`) throughout.

## 1. Read the initiative, and check it is one

Call `mcp__abacus__get_ticket`. It takes the key directly; case and
zero-padding don't matter. If "$ARGUMENTS" is a title fragment, find it with
`list_boards` then `list_tickets`, and confirm which one you landed on before
doing anything else.

**Check `type` is `initiative`.** If it isn't, stop. Say what it is, and point
at `/colormath:refine-ticket`, which is the right tool for a ticket. Do not
quietly refine a feature as if it were an initiative — the deliverable is
shaped differently and would be wrong.

**Check `initiative_status`.**

- `designing` — the normal case. The features are editable; carry on.
- `building` — **the design is closed.** Every feature write is refused by the
  server, and that is deliberate: the list is the record of what was agreed and
  the tickets have already been cut from it. Say so plainly rather than
  discovering it at the write step. You may still refine the initiative's own
  **description** if the user asks — offer that, name it as the only thing you
  can change, and get an explicit yes before writing. Never propose "just start
  a fresh initiative to get around the lock" as though it were free; the tickets
  already cut are the reason it is locked.

Then read all of it, and mean it: description, **every feature definition** in
order, **every comment**, the tickets already filed under it (`get_ticket`
returns the children — the board tools hide them), its release, its lane.
Comments are where decisions already made go to hide, and refining an initiative
into a shape that contradicts a decision recorded in its own thread is an
avoidable embarrassment.

If it already has a description or features, you are **revising, not
authoring**. Read the prior text as evidence of intent.

## 2. Investigate the architecture before you ask anything

This is where most of the time should go, and it is what separates a refined
initiative from a padded one. You are building the picture the filer assumed
everyone had.

**Start with the written decisions.** `AGENTS.md` / `CLAUDE.md`, the ADRs in
`docs/adr/`, the rules files. These state the invariants the initiative must
live inside — layering, tenancy scoping, ordering rules, audit obligations,
authorization defaults, naming. An initiative that violates one of these is the
single most valuable thing to catch, and you catch it here or not at all.

**Then the code the initiative lands in.** Routes, services, models, templates,
jobs, migrations, config. For each feature line, and for the initiative as a
whole:

- **Does it already exist?** Fully, partially, behind a flag, or built and
  deliberately removed. Something already shipped is the most useful finding you
  can bring back.
- **Where does it go?** Which layer owns it, which existing service grows a
  method, which needs to be created. Name real modules.
- **What does it force?** A new table, a migration, a new column on a hot table,
  a new event type, a new permission, a background job, a third-party
  dependency, a deploy-ordering constraint. These are the things that make an
  initiative bigger than it looks, and the reason to find them now is that they
  change what the features should even be.
- **What does it collide with?** Work in flight, an adjacent subsystem that owns
  the same data, an invariant that would have to bend. Bending an invariant is
  sometimes right — but it is a decision, and it belongs in the write-up rather
  than in a surprise six weeks later.
- **Is each feature implementable as written?** Take each one literally and ask
  what you would do on Monday. A feature nobody can start from — "make it
  faster", "handle errors properly", "improve the UX" — is not a feature yet,
  and turning it into one is half of this skill's job.
- **Do the features cover the initiative?** Look for the gaps: the migration
  nobody listed, the permission model, the empty state, the thing that has to
  happen to existing data, the surface an agent reaches over MCP. Also look for
  the opposite — features that belong to a *different* initiative.

Keep, in your head and later in the write-up, a hard line between **what you
verified in the repo** and **what you inferred**. They get labelled differently
in the output.

## 3. Interview until the picture is complete

The interview is the point of this skill, and it is a conversation rather than a
form. But it earns its cost only because step 2 happened first: you are asking
someone to choose between real options, not to explain their own idea back to
you.

Use `AskUserQuestion` with concrete options, recommendation first, and say why
it's your recommendation. **Batch into rounds** — up to four questions a round,
and let each round's answers reshape the next. Three rounds is usually plenty;
if you are still asking on the fourth, you are either designing the code (stop)
or the initiative is really several (say so).

The things that most often decide whether an initiative is right:

- **The problem behind it.** The title says what to build; it rarely says what
  goes wrong today, for whom, and how often. The obvious build frequently
  satisfies the title and misses the reason.
- **What "done" looks like for the whole initiative** — the observable that
  makes someone say it shipped. If nobody can name one, the initiative is a
  theme, and it should be split or narrowed.
- **The scope edges.** What is deliberately *not* in it, and where that work
  went instead. This is the single most valuable answer you will get.
- **The forks step 2 surfaced.** Every place two reasonable structures differ in
  a way someone would notice later: where state lives, what is derived versus
  stored, what happens to data already written, what is reversible.
- **The architectural bends.** If the initiative needs an invariant to move, put
  the choice to them explicitly, with the cost of each side. Never bend one
  silently.
- **Ordering and dependencies.** What has to exist first, inside the initiative
  and outside it — another team, a vendor, a migration that must land alone.
- **Who it is for**, when that is unclear: an internal tool and a customer
  surface are different products with the same title.

**Don't ask what you can settle.** Where a conventional default exists, take it
and write it into the initiative as a stated assumption where it can be
contradicted — cheaper for everyone than a question. And **let the answers move
you**: interviewing and then writing the design you had already drafted is worse
than not asking.

## 4. Draft the initiative, at the right altitude

Write for someone with none of the context, joining on Monday. The test for
every sentence: *does this help someone decide what to build, without telling
them how to type it?*

The initiative's **description** carries:

- **The problem** — what is true today, what is wrong with it, who it costs.
- **What this initiative is** — the shape of the change in a paragraph, in the
  system's own vocabulary.
- **Where it lands** — the real modules, services, tables and surfaces it
  touches, named. This is the section that proves you opened the repo.
- **The decisions taken**, including the ones taken in the interview and the
  options they beat. This is what stops the same argument happening twice.
- **Constraints and invariants** — the ADRs and rules it must live inside, by
  number, and anything it deliberately bends, with the reason.
- **Out of scope** — the adjacent, tempting work this is not doing, and where it
  went instead.
- **Open questions and assumptions** — everything unresolved, stated plainly. An
  initiative that admits two unknowns is worth more than one that silently
  guesses.

**Stop short of code.** No file-by-file steps, no function signatures, no DDL,
no test lists. If you catch yourself writing `services/billing.py:212`, you have
dropped an altitude — that belongs to the ticket, and
`/colormath:refine-ticket` will write it there later. Naming a *module* as the
home for a feature is the right level; naming a line is not.

Then each **feature definition** gets rewritten so that it is a thing someone
could take. A good one has:

- a **title** that names a capability, not an activity — a reader should be able
  to tell whether it is done;
- a **description** covering what it includes, what it explicitly does not, the
  surface(s) it appears on, and the observable that means it works;
- enough **background** that whoever picks it up does not have to re-derive the
  initiative to understand their piece.

Put them in **build order** where one genuinely depends on another — the order
is read as an argument, so make it one.

Where the investigation says a feature should **not exist** — already built,
belongs to another initiative, or is really three — say so in the draft. Note
that **there is no way to delete a feature definition over MCP**: recommend the
removal, name it clearly, and let the user do it in the web UI. Rewriting an
unwanted feature into a different one to avoid the awkwardness is worse than
saying it plainly.

## 5. Show it, confirm, then write it back

Show the whole draft in chat **before** writing anything: the new description,
each feature as it will read, the new order, the additions, and the removals you
are recommending but cannot make. Refining is a proposal about someone else's
intent; they get to correct it while it is still cheap.

Say explicitly what you are **overwriting** — description text and feature text
you did not write — so the loss is a decision rather than an accident.

On approval, write in this order, so a failure part-way leaves something
coherent:

1. `mcp__abacus__update_ticket` with the new `description`. Pass only the fields
   you are changing; anything omitted keeps its value. Leave `plan` and
   `qa_plan` alone — an initiative is not implemented directly, and those fields
   belong to the tickets that come out of it.
2. `mcp__abacus__update_feature` for each rewritten feature. **Both fields are
   replaced** by what you send, so send the title even when only the description
   changed, or you will clear it.
3. `mcp__abacus__add_feature` for each new one.
4. `mcp__abacus__move_feature` to put the list in the order you argued for.
   Positions are 0-based and clamp; move one at a time and re-read if you lose
   track.

Where the interview produced a decision worth keeping as a record — a rejected
approach, the reasoning behind a scope cut — `add_comment` is its home. The
description should read as the current intent, not its history.

Finish in chat with: the initiative key, what changed, what you verified against
the code versus assumed, the open questions that survived, and the removals the
user still has to make by hand. Then say what happens next — **a human starts
building when they are ready**, which cuts a ticket per feature; you cannot do
that and should not offer to.

## Rules

- **Check it is an initiative, and check its status, first.** A ticket goes to
  `/colormath:refine-ticket`. A building initiative is locked, and saying so
  early is the difference between a conversation and a failed write.
- **Investigate before you interview.** Questions from a cold read are a survey;
  questions after an architecture pass are a decision.
- **Stay above the code.** Structure, layers, invariants, ordering — yes.
  File-by-file steps, signatures, DDL, test lists — no. Those go on the tickets
  later.
- **Never bend an architectural rule silently.** If the initiative needs one to
  move, that is a question for the user and a line in the write-up, by ADR
  number.
- **Never invent an answer the user didn't give.** Unresolved goes in as a
  stated open question or a stated assumption, visibly, where it can be
  contradicted.
- **Don't implement anything.** No branches, no code edits, no PRs, no tickets
  created by hand. The refined initiative is the deliverable.
- **Don't start building.** The transition is one-way, it locks the features and
  cuts the tickets, and it is a person's decision — there is deliberately no
  tool for it. If asked, explain and hand back.
- **Say when an initiative shouldn't be built.** If the investigation shows it
  is already built, already rejected by a recorded decision, or solves a problem
  that no longer exists, that finding *is* the deliverable.
