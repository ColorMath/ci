# Recon: running stack, real credentials

Goal: a platform you can drive, and enough identities to compare what
different callers are allowed to do. Budget a few minutes — recon that drags
eats the time you need for probing.

## Getting it up

**Check whether it's already running before starting anything.** A developer's
stack is usually up, often with hours of state in it. `docker compose ps`,
`docker ps`, or a curl at the app port answers this in one call. Restarting or
reseeding somebody's working environment is a rude way to open a QA session.

Run commands live in `AGENTS.md` / `CLAUDE.md` — typically a `make up` plus a
seed target, with the port map documented alongside. Take the ports from there
rather than guessing; colormath apps deliberately avoid default ports so
several products can run at once.

Useful things to note while you're there:

- **Is the code volume-mounted?** If the compose file bind-mounts source into
  the container, a restart picks up your edits and you can verify fixes in
  seconds. If not, you're rebuilding an image each time — plan around it.
- **Which services exist beyond the app** — a worker, a mail catcher, a DB
  admin UI. The mail catcher matters: it's where you send outbound mail during
  QA instead of a real provider.
- **Sibling services that are already broken.** Note them now so you don't
  later mistake somebody else's crashloop for your finding.

If seed data is missing, seed it. If the stack is up but a dependent service
is unhealthy, say so rather than working around it silently — it may be the
first finding.

## Finding seeded accounts

Demo/seed fixtures are the fastest source. Look for a `demo/`, `seeds/`, or
`fixtures/` directory holding JSON/YAML with users in it; these commonly carry
**plaintext passwords**, because their whole purpose is a reproducible demo
login. A repo that documents its demo users (`DEMO_USERS.md` and friends) is
telling you exactly what you need.

Otherwise query the database directly. Inspect the schema before writing
`SELECT`s — column names differ (`title` vs `name`, `global_role` vs
`is_superuser`) and a failed guess costs a round trip:

```
\d users
select column_name from information_schema.columns where table_name = 'X';
```

What you're after is not one login but **the role matrix**: which accounts sit
at which tier, and in which tenant. Join the membership tables and read it off.
Note any role that is supposed to grant *no* access — a departed-user or
disabled state — because "this role should be able to do nothing" is a
high-value thing to test and is often newer, thinner code.

## Getting credentials at every tier

You need, at minimum: an admin, a mid-tier (editor/member), a read-only
viewer, someone from a **different tenant**, and any no-access role. Without
the cross-tenant identity you cannot test isolation at all, and isolation is
where the expensive bugs are.

**Minting credentials directly against the dev DB is legitimate and much
faster than driving signup or invite flows** — as long as you match how the
app issues them. Find the service that creates the credential and copy its
scheme: the token format, the hash (often `sha256` of the plaintext), which
columns it fills, and how revocation is represented. Then insert rows with
known plaintexts. Mint a deliberately revoked one too — "does a revoked
credential still work" is a one-line test that occasionally pays out.

Name the rows you create with an obvious prefix (`qa-…`) so cleanup in step 7
is a single predictable delete.

For browser/session work, the real login form is the first choice — it's the
flow users actually take, and driving it tests the login path itself. Expect a
**CSRF token** on it: fetch the login page, scrape the hidden token, post it
back with a cookie jar. If login returns 403 with no explanation, that's
almost always what's missing rather than bad credentials.

**When you cannot submit the form, mint the session server-side rather than
abandoning the UI checklist.** Typing a password into a field may be off the
table for you even with valid demo credentials in hand; a login page behind
SSO, a second factor, or a captcha blocks you the same way. None of that is a
reason to report UI items as unverified — the session is the thing you need,
and the app already knows how to create one:

1. Find the call the login route makes *after* it verifies the password —
   typically `create_session(user_id)` or equivalent — and what it puts in the
   response. Read the `set_cookie` call for the exact cookie name and flags.
2. Call that same function against the dev DB with the seeded user's id. Use
   the app's own machinery; don't hand-forge a token or a signed cookie, or
   you'll be testing your forgery rather than the app.
3. Install the cookie in the browser profile (via the automation tool's script
   execution, or a `document.cookie` write on the right origin — note that an
   `httponly` cookie must be set through the browser's cookie API, not JS), then
   navigate and proceed with the checklist normally.
4. Prefix or record what you created so cleanup destroys it: the session row
   should die with the rest of the QA debris in step 7.

This is a **local dev stack only** technique. Never mint a session against
staging, production, or any shared environment — there, an unavailable login is
a genuine blocker to report, not an obstacle to route around.

Say plainly in your report that the session was minted rather than logged into,
and mark the login flow itself as untested — that's the one thing this
technique cannot cover, and it's exactly the thing a reader will assume you
did cover.

Where the repo exposes a machine interface (an API, an MCP server), drive it
over the wire with its real transport instead of calling functions in-process.
In-process calls skip the auth middleware, the serialization layer, and the
rate limiter — which is to say they skip most of what you're trying to test.

## Sanity check before probing

Confirm each identity works and resolves to the tier you think it does — one
cheap authenticated read per credential. Discovering halfway through the
authorization matrix that your "viewer" was actually an admin invalidates
everything you've done since.

Record the baseline you'll restore later: row counts for tables you expect to
write, and the current value of any config you plan to change.
