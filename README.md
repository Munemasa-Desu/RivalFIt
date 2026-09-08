# RivalFit

Always-on head-to-head fitness. Add a friend, get a live scoreboard.
No competitions to set up, no groups to manage — the rivalry *is* the product.

## What is in this repository

Right now: the product spec and the backend that makes the differentiating
screens (`head_to_head`, `head_to_head_challenge`) possible.

```
docs/                    PRD, data model, API architecture, roadmap
  00-PRD.md
  01-USER-STORIES.md
  02-DATA-MODEL.md
  03-API-ARCHITECTURE.md
  04-FOLDER-STRUCTURE.md
  05-ROADMAP.md

supabase/
  migrations/           Numbered, idempotent, RLS-first. Applied top-down.
  seed/                 Curated exercise library + signature templates.
  functions/            Edge Function stubs (Stripe webhook, HealthKit sync,
                        deadline sweeper, invite links).
  tests/                pgTAP-style validation scripts.

app/                    (Phase 1) Expo app scaffold. See docs/04-FOLDER-STRUCTURE.md.
```

## Local database

```bash
initdb -D /var/tmp/rfpg -U postgres --auth=trust
pg_ctl -D /var/tmp/rfpg -o "-p 55432 -k /var/tmp" -l /var/tmp/pg.log start

psql -h /var/tmp -p 55432 -U postgres -c "create database rivalfit;"
psql -h /var/tmp -p 55432 -U postgres -d rivalfit -f supabase/tests/00_supabase_stub.sql
for f in supabase/migrations/*.sql supabase/seed/*.sql; do
  psql -h /var/tmp -p 55432 -U postgres -d rivalfit -v ON_ERROR_STOP=1 -f "$f"
done
```

The stub in `supabase/tests/00_supabase_stub.sql` fakes the pieces Supabase
adds to a hosted project (`auth.uid()`, the API roles) so migrations can be
validated on any vanilla Postgres 16. In a real Supabase project it is not
applied — Supabase provides those objects itself.

## Start reading here

1. [`docs/00-PRD.md`](docs/00-PRD.md) — problem, thesis, the two screens.
2. [`docs/02-DATA-MODEL.md`](docs/02-DATA-MODEL.md) — schema tour, RLS,
   trigger flow, scoring math.
3. [`docs/03-API-ARCHITECTURE.md`](docs/03-API-ARCHITECTURE.md) — direct-to-
   Postgres vs Edge Function, per screen.
4. [`docs/05-ROADMAP.md`](docs/05-ROADMAP.md) — the four phases and what
   ships in each.
