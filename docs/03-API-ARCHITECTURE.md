# API architecture

The mobile client is talking to two things:

- **PostgREST** for tables and views the schema is willing to expose. This
  covers almost all reads and about 80 % of writes.
- **Edge Functions** (Deno on Supabase) for anything that touches an
  external service, holds a secret, needs to run outside a user session,
  or must not be spoofable by the client.

The dividing line is a single question: *does the operation require a
resource, secret, or invariant the RLS layer cannot express?* If yes, it is
an Edge Function. If no, it is a direct table/view call.

## 1. Direct-to-Supabase (PostgREST)

### 1.1 Reads

| Screen                | Query                                                    |
|-----------------------|----------------------------------------------------------|
| Head-to-Head          | `from('head_to_head').select('*')`                        |
| Head-to-Head Challenge| `from('head_to_head_challenge').select('*').eq('instance_id', id)` |
| Feed                  | `from('rivalry_feed').select('*').eq('rivalry_id', id).order('created_at', {ascending:false}).limit(50)` |
| My workouts           | `from('workouts').select('*, workout_sets(*)').eq('user_id', me).order('completed_at', {ascending:false})` |
| PR list               | `from('personal_records').select('*, exercises(name, slug)').eq('user_id', me)` |
| Template catalogue    | `from('challenge_templates').select('*, challenge_template_steps(*, exercises(*))').not('published_at','is',null)` |
| Discovery             | `rpc('search_profiles', { p_query: term })`               |

### 1.2 Writes (all RLS-gated)

- Profile edits, block/unblock.
- Send rivalry request; accept / decline / pause / end.
- Create workout, add sets, mark completed. (Two statements, one txn.)
- Send taunts (with the DB-side rate limit).
- Create a challenge instance for a rivalry.
- Update an attempt's `state`, `started_at`, `completed_at`, `elapsed_s`.
- Append rows to `challenge_attempt_steps`.

### 1.3 Realtime channels

| Channel                                          | Consumer                              |
|--------------------------------------------------|---------------------------------------|
| `rivalry_scores:rivalry_id=eq.<id>`              | Head-to-Head screen                   |
| `rivalry_events:rivalry_id=eq.<id>`              | Feed strip                            |
| `challenge_attempt_steps:attempt_id=eq.<mine>`+`=eq.<theirs>` | Race view splits         |
| `challenge_attempts:instance_id=eq.<id>`         | Race view state                       |

Realtime respects the same RLS as reads, so filters do not need to include
`user_id` — the server drops rows the caller cannot see anyway.

## 2. Edge Functions (`supabase/functions/`)

The stubs live in the repository. Each has a one-page implementation TODO
inside the file.

### 2.1 `stripe-webhook`

- Runs as **service role**. Signature verified with
  `Stripe.webhooks.constructEventAsync(payload, sig, secret)`.
- Inserts into `stripe_events` first — primary key `event_id` gives us
  idempotency for free (Stripe retries land as no-ops).
- Then updates `subscriptions` from the event's data.
- Emits a `subscription.updated` payload to Realtime channel
  `subscriptions:user_id=eq.<id>` so the client's Pro badge flips
  without a refetch.

### 2.2 `create-checkout-session` / `create-billing-portal`

- User-scoped: uses the caller's JWT to look up their `stripe_customer_id`
  (creating one on Stripe if missing) and returns a session URL.
- Never trusts client-supplied `price_id`; the price ids are stored in
  Function env vars and picked by product code.

### 2.3 `create-invite`

- Server-generates a short code, signs it, and stores it in `invite_codes`
  (post-MVP addition; not in migrations yet). Serves an OG-tagged
  landing page for iMessage/WhatsApp previews.
- Redemption is client-side once signed in: the client calls
  `redeem_invite(code)` which creates the pending rivalry as an RPC.

### 2.4 `healthkit-sync` / `googlefit-sync`

- Called by the app *after* a HealthKit/HealthConnect background sync
  hands the client new workout envelopes. The function normalises and
  upserts into `workouts` with `source = 'healthkit'` / `'google_fit'`,
  keyed by `external_id` for idempotency.
- Runs with the user's JWT — not service role — so RLS still applies.
  The reason it is an Edge Function at all is the normalisation library
  and the exercise-mapping table live outside the phone bundle.

### 2.5 `sweep-challenges` (scheduled)

- Runs every 5 minutes via `pg_cron`. Two-line implementation:
  ```sql
  select rf.sweep_expired_challenges();
  ```
- Kept as an Edge Function (rather than pure pg_cron) so we can wire
  logging, alerting, and the Realtime nudge for the losing party.

### 2.6 `close-weekly` (scheduled)

- Runs at 00:05 UTC every Monday.
  ```sql
  select rf.close_finished_weeks();
  ```
- Fans out weekly-recap push notifications by iterating the events
  it just emitted.

### 2.7 `send-push`

- Fires on `rivalry_events` inserts via a Postgres `LISTEN` bridge
  (`pg_notify('rivalry_event', new_id::text)` from `rf.emit_event`).
- Looks up Expo push tokens for the other party of the rivalry,
  respects the receiver's notification preferences.
- Payloads are small and deep-link into the right screen
  (`rivalfit://rivalry/<id>` or `rivalfit://challenge/<instance>`).

### 2.8 `verify-attempt` (Phase 4)

- Accepts a proof media upload id, runs OCR/basic validation, sets
  `challenge_attempts.verified = true`. Explicitly not in the MVP;
  documented to keep the boundary honest.

## 3. Why anything is not an Edge Function

Common temptations, and why they stay direct:

- **"Wrap all writes in a service function for logging."** RLS already
  answers the "who is allowed to do this" question, and PostgREST logs
  every request. A wrapper is just a place bugs hide.
- **"Compute the head-to-head server-side to avoid schema exposure."** The
  view *is* the server-side computation, and RLS makes it safe. Wrapping
  it in a function loses Realtime.
- **"Enforce challenge integrity in an Edge Function."** The
  `rf.guard_attempt_transition` trigger enforces it in the database, which
  cannot be bypassed by any client, including our own.

## 4. Security-in-depth summary

| Layer            | Enforces                                                        |
|------------------|-----------------------------------------------------------------|
| Auth (JWT)       | Who the caller is; every RLS `select auth.uid()` reads this    |
| Column grants    | Which columns clients may write (e.g. no `points` write)        |
| RLS policies     | Which rows a caller may see, insert, update, delete             |
| Row triggers     | Illegal transitions and derived values (scores, streaks, points)|
| Constraints      | Ranges, enums, referential integrity                            |
| Edge Functions   | External systems, secrets, cross-user actions with the service role |

A bypass at any single layer is limited by the others. Losing the JWT
still requires knowing the target ids and running afoul of the trigger
guards; a compromised trigger still cannot exceed the column grants; a
mistaken Edge Function is still bounded by what the API roles are granted.

## 5. Rate limits

- **Taunts.** 10 per hour per sender, in the DB via
  `rf.guard_taunt`.
- **Rivalry requests.** 20 per day per sender, enforced by the
  `create-invite` Edge Function *and* a partial-unique index on
  `(requested_by, user_a, user_b)` with status `pending`.
- **`search_profiles`.** Minimum 3 chars, cap 20 rows, in the RPC.
- **Everything else.** PostgREST's default per-IP limits and Supabase's
  project-level protections. If we outgrow those we introduce a proper
  API gateway; we do not sprinkle rate-limit tables prematurely.
