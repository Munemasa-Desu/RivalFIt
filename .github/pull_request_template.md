## What this changes


## Why


## Screens / migrations touched


## How I validated it

- [ ] `supabase/tests/run.sh` passes locally
- [ ] Types regenerated (`pnpm --dir app gen:types`) if a public column changed
- [ ] No new client-writable columns on trigger-owned fields (points, score, streaks, PRs)
- [ ] RLS policies added for every new table

## Notes for the reviewer

