# Folder structure

```
RivalFIt/
├─ README.md
├─ docs/
│   ├─ 00-PRD.md
│   ├─ 01-USER-STORIES.md
│   ├─ 02-DATA-MODEL.md
│   ├─ 03-API-ARCHITECTURE.md
│   ├─ 04-FOLDER-STRUCTURE.md
│   └─ 05-ROADMAP.md
│
├─ supabase/
│   ├─ config.toml                  Supabase CLI project config
│   ├─ migrations/                  Numbered, apply top-down, idempotent
│   │   ├─ 20260907000100_extensions.sql
│   │   ├─ 20260907000200_helpers.sql
│   │   ├─ 20260907000300_profiles.sql
│   │   ├─ 20260907000400_social.sql
│   │   ├─ 20260907000450_events.sql
│   │   ├─ 20260907000500_exercises.sql
│   │   ├─ 20260907000600_workouts.sql
│   │   ├─ 20260907000700_billing.sql
│   │   ├─ 20260907000800_challenges.sql
│   │   ├─ 20260907000900_scoring.sql
│   │   └─ 20260907001000_views.sql
│   │
│   ├─ seed/                        Data seeds (exercises, templates)
│   │   ├─ 010_exercises.sql
│   │   └─ 020_templates.sql
│   │
│   ├─ functions/                   Deno Edge Functions (stubs)
│   │   ├─ _shared/                     supabase client, JSON helpers
│   │   ├─ stripe-webhook/index.ts
│   │   ├─ create-checkout-session/index.ts
│   │   ├─ create-billing-portal/index.ts
│   │   ├─ create-invite/index.ts
│   │   ├─ healthkit-sync/index.ts
│   │   ├─ googlefit-sync/index.ts
│   │   ├─ sweep-challenges/index.ts
│   │   ├─ close-weekly/index.ts
│   │   └─ send-push/index.ts
│   │
│   └─ tests/                       Local validation
│       ├─ 00_supabase_stub.sql     Fakes auth.uid()/roles on vanilla PG
│       ├─ 10_rivalry_rls.sql
│       ├─ 20_workout_scoring.sql
│       └─ 30_challenge_race.sql
│
└─ app/                             Expo (React Native)
    ├─ app.json
    ├─ package.json
    ├─ tsconfig.json
    ├─ babel.config.js
    ├─ eas.json
    ├─ index.ts
    │
    ├─ assets/
    │   ├─ icons/                       Category icons for template cards
    │   └─ fonts/
    │
    └─ src/
        ├─ app/                     File-based routes (expo-router)
        │   ├─ _layout.tsx              Root stack + auth gate + theme provider
        │   ├─ (auth)/
        │   │   ├─ sign-in.tsx
        │   │   └─ sign-up.tsx
        │   ├─ (tabs)/                  Rivals · Log · Challenges · Me
        │   │   ├─ _layout.tsx
        │   │   ├─ index.tsx            Rivals list (pager)
        │   │   ├─ log.tsx              Start / resume workout
        │   │   ├─ challenges.tsx       Template catalogue
        │   │   └─ me.tsx               Profile + PRs + settings
        │   ├─ rivalry/
        │   │   ├─ [id].tsx             Head-to-Head screen (5.1)
        │   │   └─ [id]/feed.tsx        Full-feed drill-down
        │   ├─ challenge/
        │   │   ├─ [instanceId].tsx     Race view (5.2)
        │   │   └─ new/[templateId].tsx Configure & confirm start
        │   ├─ workout/
        │   │   ├─ [id].tsx             Live logger
        │   │   └─ review/[id].tsx      Post-workout summary
        │   ├─ invite/[code].tsx        Deep-link handler for invites
        │   └─ paywall.tsx
        │
        ├─ components/              Presentational, no data fetching
        │   ├─ HeadToHeadBar.tsx        The single-bar split
        │   ├─ StatRow.tsx
        │   ├─ AvatarStack.tsx
        │   ├─ ChallengeCard.tsx
        │   ├─ RaceLane.tsx             One lane of the race view
        │   ├─ FeedItem.tsx
        │   ├─ TauntSheet.tsx
        │   └─ empty/                   Empty-state components per screen
        │
        ├─ features/                Feature-scoped hooks, stores, services
        │   ├─ auth/
        │   │   ├─ auth.store.ts
        │   │   ├─ useSession.ts
        │   │   └─ oauth.ts
        │   ├─ rivalry/
        │   │   ├─ rivalry.api.ts         Supabase queries against head_to_head
        │   │   ├─ rivalry.realtime.ts    Channel subscriptions
        │   │   ├─ rivalry.store.ts       Zustand slice: current rivalry id
        │   │   ├─ useHeadToHead.ts       React Query wrapper
        │   │   ├─ useRivalryFeed.ts
        │   │   └─ useTauntMutation.ts
        │   ├─ workout/
        │   │   ├─ workout.api.ts
        │   │   ├─ workout.store.ts       Draft workout, local set queue
        │   │   ├─ sync.ts                Offline queue drain
        │   │   ├─ useStartWorkout.ts
        │   │   ├─ useCompleteWorkout.ts
        │   │   └─ pr.ts                  Derives on-device projections
        │   ├─ challenge/
        │   │   ├─ challenge.api.ts
        │   │   ├─ challenge.realtime.ts
        │   │   ├─ useCatalogue.ts
        │   │   ├─ useStartChallenge.ts
        │   │   ├─ useLogSplit.ts
        │   │   └─ useDecideCountdown.ts  Deadline-driven UI ticker
        │   ├─ billing/
        │   │   ├─ billing.api.ts         Calls Edge Functions
        │   │   ├─ useEntitlement.ts      Reads subscriptions
        │   │   └─ Paywall.tsx
        │   └─ notifications/
        │       ├─ expo-push.ts
        │       └─ registerForPush.ts
        │
        ├─ lib/                     Cross-feature utility
        │   ├─ supabase.ts               createClient with persisted session
        │   ├─ queryClient.ts            React Query defaults
        │   ├─ theme.ts                  colors, spacing, type ramp
        │   ├─ format.ts                 duration, distance, weight formatters
        │   ├─ time.ts                   week/month boundary math (mirrors rf.period_start)
        │   ├─ realtime.ts               Wrapper that RLS-checks channels
        │   ├─ analytics.ts
        │   └─ errors.ts
        │
        ├─ types/
        │   ├─ database.ts               `supabase gen types typescript`
        │   └─ domain.ts                 Hand-authored view models
        │
        └─ tests/
            ├─ setup.ts
            ├─ features/rivalry.test.ts
            └─ features/challenge.test.ts
```

## Conventions

- **File-based routing via expo-router.** Every screen has one URL. Push
  notifications deep-link to those URLs, not to a JS navigation object.
- **Zustand for local UI state, React Query for server state.** No global
  Redux store, no context providers doing data fetching. `rivalry.store.ts`
  holds "which rivalry is the user looking at right now"; the head-to-head
  numbers themselves come from React Query so refetch and Realtime updates
  compose.
- **Feature folders own their Supabase calls.** No `src/api/` bag of
  functions. If it belongs to `challenge`, it lives in `features/challenge`.
- **Components are dumb.** A component takes props and renders. If it
  needs data, its parent screen has a hook. This makes the screens easy
  to storybook and the components trivial to reuse.
- **Types come from Postgres.** `types/database.ts` is regenerated with
  `supabase gen types typescript` on every migration; nothing hand-written
  duplicates a column name.
- **Time math mirrors SQL.** `lib/time.ts` implements `weekStart(date)`
  and `monthStart(date)` in UTC, matching `rf.period_start`. A mismatch
  here was previously the whole "why is my week off by a day?" class of
  bug.
