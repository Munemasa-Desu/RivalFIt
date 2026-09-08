# Documentation index

| Document | What it covers |
|----------|----------------|
| [`00-PRD.md`](00-PRD.md) | Product requirements, thesis, target user, the two differentiating screens, success metrics, tenets. |
| [`01-USER-STORIES.md`](01-USER-STORIES.md) | Six epics, prioritized stories, acceptance criteria, and the system pieces implementing each. |
| [`02-DATA-MODEL.md`](02-DATA-MODEL.md) | Schema tour, RLS design, trigger flow, scoring math, and the four "bug shapes" worth knowing. |
| [`03-API-ARCHITECTURE.md`](03-API-ARCHITECTURE.md) | Direct-to-Supabase vs Edge Functions, per screen and per write. Security-in-depth summary. |
| [`04-FOLDER-STRUCTURE.md`](04-FOLDER-STRUCTURE.md) | Repository layout with conventions per folder. |
| [`05-ROADMAP.md`](05-ROADMAP.md) | Phases 0–4, exit criteria, and the "explicitly not doing" list. |

## Where things live in code

| Concern | Path |
|---------|------|
| Migrations | `supabase/migrations/` (numbered, apply top-down) |
| Seed exercises & templates | `supabase/seed/` |
| Edge Functions | `supabase/functions/` |
| End-to-end DB validation | `supabase/tests/` (`./supabase/tests/run.sh`) |
| Mobile app | `app/` (Expo, TypeScript, expo-router) |
| Head-to-Head screen | `app/src/app/rivalry/[id].tsx` |
| Race view | `app/src/app/challenge/[instanceId].tsx` |
| Data models | Views `public.head_to_head`, `public.head_to_head_challenge`, `public.rivalry_feed` |
