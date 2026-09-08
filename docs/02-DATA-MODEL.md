# Data model

Every design decision here traces back to one of two constraints:

- **The head-to-head screen must open instantly and stay live.** That means
  scoreboards are maintained incrementally on write, not aggregated on read,
  and every downstream state (streaks, PRs, feed events, challenge decisions)
  is a trigger's job rather than the client's.
- **RLS is the API.** The mobile client hits PostgREST directly for almost
  everything (see `03-API-ARCHITECTURE.md`), so the schema itself has to
  enforce the rules. There is no server-side "controller" layer.

The migrations in `supabase/migrations/` are numbered so they apply top-down;
they were validated against a live Postgres 16 during authorship.

---

## 1. Schemas

| Schema      | Contents                                                                 |
|-------------|--------------------------------------------------------------------------|
| `public`    | Tables and views the client queries via PostgREST                        |
| `rf`        | Internal helpers, enums, trigger functions, scoring math                 |
| `extensions`| `pgcrypto` and (post-MVP) any other extensions                           |
| `auth`      | Supabase-managed (stub in `supabase/tests/00_supabase_stub.sql`)         |

`SECURITY DEFINER` functions all pin `search_path = ''` and fully qualify
every object reference. A caller cannot shadow a name (e.g. by creating a
`public.workouts` view in another schema on the same session) and hijack the
elevated context.

## 2. Table map

```
profiles          one per auth.users, created by signup trigger
  │
  ├─ blocks              blocker_id → profiles, unilateral
  │
  ├─ rivalries           ordered pair (user_a < user_b) + status
  │    │
  │    ├─ rivalry_events append-only feed, no FK on subject_id
  │    ├─ rivalry_scores incremental per (rivalry, user, period, week_start)
  │    ├─ rivalry_results closed-week outcomes for the head-to-head record
  │    └─ challenge_instances one rivalry vs one template, per race
  │         └─ challenge_attempts   one per user per instance, seeded on create
  │              └─ challenge_attempt_steps  per-station splits
  │
  ├─ subscriptions       stripe mirror, service-role writes only
  │
  ├─ workouts            source of truth for scoring
  │    └─ workout_sets   per-exercise details
  │
  ├─ personal_records    one per (user, exercise, metric)
  └─ taunts              rate-limited, RLS to the rivalry

exercises                library; created_by IS NULL = official
challenge_templates      versioned; frozen after publish
challenge_template_steps embedded exercises + targets
```

## 3. The two decisions worth their own section

### 3.1 Ordered-pair rivalries

`rivalries` stores each pair with `user_a < user_b`. A `BEFORE INSERT`
trigger swaps them if the client sends them in the "wrong" order.

Why: "is there a rivalry between these two?" becomes a single unique-index
probe instead of a two-branch `OR`, and the unique constraint alone
prevents duplicate pairs. The scoreboard fan-out (`rf.on_workout_completed`)
does not care which slot the user is in — it iterates rivalries where
`user_id IN (r.user_a, r.user_b)`.

### 3.2 One row per (rivalry, athlete, period)

The obvious model — `rivalry_scores(rivalry_id, a_points, b_points, ...)` —
looks compact but is a trap. Every trigger has to branch on "am I `user_a`
or `user_b`?" and the head-to-head view has to CASE-when across every column.
The narrow model instead:

```
primary key (rivalry_id, user_id, period, period_start)
```

Fan-out is a plain `UPSERT`; the head-to-head view is a self-join on
`rivalry_id`; the Realtime subscription is a single `filter=rivalry_id=eq.…`
and both athletes' rows arrive in the same channel.

## 4. Trigger flow: what happens when a workout is finished

1. Client `UPDATE workouts SET status='completed', ended_at=now(), duration_s=…`
2. `workouts_finalize` (BEFORE UPDATE, gated on status transition) stamps:
   - `completed_at`, `ended_at`, `duration_s`
   - `points := rf.compute_workout_points(...)`
   - `counts_for_score := (workouts_today < 3)` — anti-grind cap
3. `workouts_on_completed` (AFTER UPDATE, same gate) fans out:
   - Increments `profiles` counters and streak (day-based in athlete's tz)
   - Upserts one PR row per `(exercise, metric)` — see 5.2
   - Emits `workout_logged` to `rivalry_events` for each active rivalry
   - `rf.bump_rivalry_scores(...)` upserts `rivalry_scores`
     for `week`, `month`, `all_time`
   - Emits `lead_change` if the athlete just took this week's lead and had
     not already held it since the rival last led — see 5.3

Point 3 is the single fan-out. Anything else that wants to react to a
workout should listen on `rivalry_events` via Realtime rather than growing a
trigger here.

## 5. Choices with a bug shape you should know

### 5.1 Cross-CTE RLS visibility

`INSERT INTO workouts` followed by `INSERT INTO workout_sets` in *sibling*
CTEs of one statement will trip RLS on `workout_sets` — the sub-select
that checks "do I own this workout?" runs against a snapshot that does not
include the sibling CTE's write. Two statements in one transaction is
fine. The Expo client already does this because of local IDs, so this
mostly matters for anyone writing raw SQL against the API.

### 5.2 PR aggregation before ON CONFLICT

`rf.on_workout_completed` inserts PR candidates. If you write "5x5 back
squat" that produces five identical `(user, exercise, 'max_weight_kg')`
rows and Postgres refuses (`ON CONFLICT DO UPDATE command cannot affect
row a second time`). We pre-aggregate to `max(value)` per
`(exercise_id, metric)` inside the fan-out. The trap is easy to walk into
again if you extend the PR list.

### 5.3 Lead-change de-duplication

Every workout that keeps the current leader ahead would otherwise emit a
`lead_change`. We only emit if there is no `lead_change` for this athlete
this week that is more recent than the last event where the *other* athlete
led. If you change scoring, verify this rule still holds by rebuilding a
scoreboard from source (see 6) and checking event counts.

### 5.4 Server clock owns the challenge

`rf.stamp_attempt_score` reads from `NEW`, not by re-selecting the row,
because it fires BEFORE UPDATE. `elapsed_s` is computed from `started_at`
and `completed_at` — the client may supply `elapsed_s` only when
`started_at` is null (offline attempts), and such an attempt stays
`verified = false`. This is what stops a phone with a bent clock from
winning a race.

## 6. Repair

Incremental counters drift eventually — a deploy rolls back mid-write, an
edit rewrites history, a backup is restored. `rf.recompute_rivalry_scores
(p_rivalry uuid)` rebuilds one rivalry's board from `workouts` +
`challenge_instances`. Safe to run at any time and diffed against live
state in the end-to-end validation (see the "diff should be empty" step in
`supabase/tests/`).

## 7. Extension points designed in

- **Group brackets.** Not a new object — a bracket is a set of rivalries.
  A `brackets` table joins to `rivalries` many-to-one; every screen the
  bracket needs is a `GROUP BY bracket_id` over `head_to_head`.
- **Custom challenges.** Users can already author drafts. A separate
  gallery view + a review flow lifts drafts to `published_at = now()`.
- **Referees.** Add a nullable `verified_by` on `challenge_attempts`; keep
  the `verified` boolean where it is.
- **HRV / recovery data.** Read-only: a new table
  `recovery_snapshots(user_id, at, hrv, ...)` referenced from the sidebar,
  never used to gate scoring.

## 8. Constraint tests worth writing (`supabase/tests/`)

- Sender cannot self-accept a pending rivalry.
- Blocking during an active rivalry ends it and prevents re-invite.
- Third parties see zero rows in `head_to_head` and `rivalry_events`.
- `search_profiles('ab')` returns 0 rows (minimum length).
- A workout with 5 identical (exercise, metric) sets produces exactly one
  PR row.
- The Hyrox instance decides on the athlete with the lower `elapsed_s`.
- `rf.recompute_rivalry_scores` produces a zero-row diff against the
  incremental state after a busy day.
