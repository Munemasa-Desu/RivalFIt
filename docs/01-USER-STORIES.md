# User stories

Each story lists (1) the user goal, (2) the acceptance criteria, and (3) the
system pieces that make it work — table, trigger, view, or Edge Function.
Priorities are P0 (MVP-blocking), P1 (launch-blocking), P2 (post-launch).

---

## Epic A · Get an account, get a rival

### A1 (P0) Sign up

> As a new user, I can sign up with Apple, Google, or email and have a
> profile ready to use.

- Sign-in completes in one round trip; the profile row is created by the
  auth trigger, so the client never has to "create my profile".
- Handle is derived from `full_name` / `preferred_username` /
  email-local-part, deduped by suffix, or falls back to a random handle if
  five suffix attempts collide.
- If any part of the trigger errors, signup fails cleanly rather than
  leaving an auth user with no profile.

*System.* `rf.handle_new_user()` on `auth.users` insert; `public.profiles`
constraints; `rf.ensure_subscription_row()` seeds a free-tier row.

### A2 (P0) Set my handle and unit system

> As a signed-in user, I can pick a memorable handle and choose metric or
> imperial units.

- Handle is 3–20 chars, `[a-z0-9_]`, unique.
- Updates that touch server-owned columns (`total_workouts`,
  `points_all_time`, `current_streak`, `longest_streak`, `last_workout_at`)
  are denied by column-level grants, not by client-side validation.

*System.* `profiles_update_self` policy; column grants in 0003.

### A3 (P0) Find someone and invite them as a rival

> As a user, I can search for someone by handle or name and send a rivalry
> request. I can also send a link that opens the app and auto-populates the
> invite.

- Prefix search only, minimum 3 chars, capped at 20 results.
- Cannot find or invite anyone I have blocked, or who has blocked me.
- Cannot invite someone I already have a live or pending rivalry with.
- The link contains a signed short code that resolves server-side, so a
  pasted link never leaks a profile id.

*System.* `public.search_profiles()`; unique index on the ordered pair;
`rf.reject_blocked_rivalry()` trigger; `create-invite` Edge Function.

### A4 (P0) Accept, decline, pause, end, or restart a rivalry

> As the receiver of a request I can accept or decline. Either of us can
> pause or end an active rivalry, and re-add later.

- The sender cannot accept their own request.
- Ending a rivalry preserves history — no row is deleted, and the
  scoreboard the next rivalry starts on is fresh.

*System.* `rf.guard_rivalry_transition()`; RLS on `rivalries`.

### A5 (P0) Block someone

> As a user, I can block another user; existing rivalry ends immediately
> and they cannot re-invite me.

- Block is unilateral: only the blocker sees the row (there is intentionally
  no policy that lets the blocked user see it).
- Blocking during a live rivalry auto-terminates it.

*System.* `rf.end_rivalry_on_block()`; `rf.reject_blocked_rivalry()`.

---

## Epic B · The Head-to-Head Screen

### B1 (P0) See my rivals immediately on open

> As a user with at least one active rivalry, the app opens directly on
> the head-to-head view.

- One rivalry → open it. Multiple → a horizontal pager, with the most
  recently active by feed time first.
- Rendered from a single `select * from head_to_head` per rivalry.
- Subscribes to `rivalry_scores` filtered on `rivalry_id` so updates for
  either athlete refresh the same view.

*System.* View `public.head_to_head`; Realtime subscription.

### B2 (P0) See who is ahead this week at a glance

> The big-number split shows my week points vs my rival's; the record row
> shows our closed-week wins.

- The split is `me_week_points / (me + them)`.
- All values are UTC-week-bucketed (`rf.period_start`), consistent across
  triggers and closeout.

*System.* `head_to_head` view; `rivalry_scores` table; `rivalry_results`
table populated by `rf.close_finished_weeks()`.

### B3 (P0) See a live feed of what my rival is doing

> When my rival finishes a workout, sets a PR, takes the lead, or starts a
> challenge, I see it in the feed within a few seconds.

- Uses Supabase Realtime on `public.rivalry_events`, RLS-filtered so I
  only get events for my rivalries.
- Events are append-only (no FK on `subject_id`) so deleting a workout
  does not vacuum its lead-change out of history.

*System.* `rivalry_events` + `rf.emit_event`; `on_workout_completed` fan-out.

### B4 (P1) Send a taunt

> I can send my rival a short taunt from a preset list or as free text.

- 140-char cap. Ten per hour, database-enforced.
- Cannot taunt anyone but my rival — enforced by trigger, not by client.

*System.* `taunts` + `rf.guard_taunt()`; `rivalry_events` emission.

---

## Epic C · Logging workouts

### C1 (P0) Log a workout by exercise and sets

> I can start a workout, add sets, and finish. Only completion moves the
> scoreboard.

- Draft workouts stay `in_progress` and are not visible to my rival.
- Completing stamps `points` server-side via `rf.compute_workout_points`.
- Per-day cap of 3 scoring workouts; the 4th and beyond still show but
  set `counts_for_score = false`.

*System.* `workouts`, `workout_sets`, `rf.finalize_workout`,
`rf.on_workout_completed`.

### C2 (P0) See my PRs update automatically

> Beating my prior best in weight, reps, distance, or duration on any
> exercise records a PR.

- One row per `(user, exercise, metric)`; only an actually-higher value
  overwrites, and the fan-out pre-aggregates per exercise so a 5x5 set
  scheme does not error on ON CONFLICT.

*System.* `personal_records` + upsert inside `rf.on_workout_completed`.

### C3 (P1) Import from Apple Health / Google Fit

> I can toggle "import my Apple Watch workouts" and they appear as
> `source = 'healthkit'`.

- Idempotent by `(user_id, source, external_id)`.
- Imports are logged like manual workouts and score identically, unless
  they duplicate an existing manual workout on the same slot.

*System.* `healthkit-sync` and `googlefit-sync` Edge Functions.

### C4 (P2) Offline logging

> In a garage or overseas, I can log sets without network; they sync when I
> reconnect.

- Client persists a queue; each item is idempotent (client-generated UUID).
- Sync path is the same insert; server clock still owns completion time.

*System.* Client-side WatermelonDB-style local store; sync helpers in
`app/src/features/workout/sync.ts`.

---

## Epic D · Challenges

### D1 (P0) Browse the template catalogue

> Every signed-in user can see every published template, whether they have
> Pro or not.

- Free users see the Pro lock affordance but the same card.
- Filter by category and equipment; sort by difficulty and estimated time.

*System.* RLS `ct_select_published`; `challenge_templates` + steps.

### D2 (P0) Start a challenge against my rival

> I pick a template, set a deadline, and confirm. My rival gets a push
> notification and an attempt lane appears for both of us.

- One live challenge per template per rivalry (unique partial index).
- `template_version` is pinned at insert-time; a later edit of the
  template does not retroactively change the race.
- If the template `requires_pro`, only a Pro user can start it — but the
  race unlocks for the free rival too.

*System.* `rf.prepare_challenge_instance`, `rf.seed_challenge_attempts`.

### D3 (P0) Race the challenge

> I press Start when I begin, log each station's split, and press Done.
> Live splits appear on my rival's phone as I go.

- `started_at` is server-stamped on the not_started → in_progress
  transition; the client cannot backdate the start.
- Steps append to `challenge_attempt_steps` with cumulative `split_s`.
- The instance flips `open → live` on the first Start.

*System.* `rf.guard_attempt_transition`, `on_attempt_state_change`.

### D4 (P0) See who won automatically

> When both of us finish (or the deadline passes) the winner is decided
> without either of us pressing anything.

- Both finished → higher score per template's scoring type wins; equal =
  draw.
- One finished, the other timed out or DNF'd → the finisher wins.
- Nobody finished by the deadline → expired, no scoreboard impact.

*System.* `rf.decide_challenge`; `rf.sweep_expired_challenges` runs
every ~5 minutes via pg_cron.

### D5 (P1) Attach proof

> I can attach a photo or a screenshot of my watch to my attempt.

- `proof_url` on `challenge_attempts`; upload goes to a Supabase Storage
  bucket with a strict per-user prefix policy.
- `verified` remains `false` unless a Pro-tier verification path is used
  (Phase 4).

*System.* Storage bucket `challenge-proof` with RLS; `challenge_attempts.proof_url`.

### D6 (P2) Rematch

> Once a race is decided, I can rematch on the same template with one tap.

- Creates a fresh instance with a new deadline; the previous instance is
  in `decided`/`expired` so the unique-live-per-template index allows it.

*System.* `challenge_instances`; unique partial index on `(rivalry_id, template_id) where state in ('open','live')`.

---

## Epic E · Billing

### E1 (P1) Subscribe to Pro

> I can subscribe from inside the app; billing is via Stripe.

- Client calls `create-checkout-session` Edge Function → Stripe hosted
  checkout → webhook writes `subscriptions.tier = 'pro'`.
- Grace period: entitlement is `tier = 'pro' AND (current_period_end IS
  NULL OR current_period_end > now())` so a missed webhook cannot keep
  a lapsed sub open indefinitely.

*System.* Edge Functions `create-checkout-session`, `stripe-webhook`,
`create-billing-portal`; `subscriptions`, `stripe_events`.

### E2 (P1) Manage or cancel

> I can open Stripe's billing portal to update card or cancel.

*System.* `create-billing-portal` Edge Function.

### E3 (P2) Team / Duo plan

> Two friends can share a Pro subscription cheaper than two individuals.

*System.* Post-launch: adds `subscription_members` join table; entitlement
check widens to `s.user_id = me OR (me ∈ subscription_members)`.

---

## Epic F · Notifications

### F1 (P0) Rival activity

> Push when my rival completes a workout, takes the weekly lead, starts a
> challenge, or wins a race.

*System.* `send-push` Edge Function subscribed to `rivalry_events` via a
Postgres LISTEN/NOTIFY bridge; Expo push tokens on `profiles`.

### F2 (P1) Weekly close-out

> First thing Monday, both rivals get "You won the week 42 → 31" or
> "Ben edged you 42 → 38".

*System.* `rf.close_finished_weeks()` on pg_cron; `weekly-recap` Edge
Function sends the push with the recap card.
