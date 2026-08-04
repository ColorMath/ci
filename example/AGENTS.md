# colormath example app

A deliberately minimal colormath consumer, kept alive so the gate suite has a
compliant app to run against on every PR. See [README.md](README.md) for what
each contract file is for.

Shared colormath conventions (CI gates, shipping, guardrails): @AGENTS.colormath.md

## Commands

Run any gate's local mirror with `make <target>` once you `include
Makefile.colormath` — this example has no `Makefile` of its own, since CI
invokes the gates directly.

## Architecture

`example_pkg/service.py` holds the logic, `example_pkg/web.py` the FastAPI
surface, `main.py` the entrypoint. There is no database beyond the single
alembic revision the `migrations` gate needs.

Keep it small. If a gate needs new surface to test, add the least code that
exercises it.
