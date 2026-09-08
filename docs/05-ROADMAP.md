# Roadmap

Four phases, ordered by risk to the thesis. Each phase ends with a demoable
build. The migrations and validation in this repository cover Phase 0
end-to-end; Phases 1–4 are the app and Edge Function work sitting on top.

Timelines are pessimistic for a two-engineer team. Halve them for a stronger
team; double them if the founder is designing solo.

---

## Phase 0 · Foundation (✅ complete in this repo)

**Ships:** the database, the RLS policies, the trigger flow, the two
signature views, seed data for four challenge templates, an end-to-end
validation script.

**Why first.** The whole product hinges on the head-to-head screen
rendering from one query and staying live. If the schema does not support
that, nothing built on top matters.

**Done means:**
- Every migration applies clean on a fresh Postgres 16.
- Every table has RLS on and at least one policy.
- End-to-end validation: two users, accepted rivalry, workouts, scoring,
  PRs, a full challenge race, and `rf.recompute_rivalry_scores` produces
  a zero-row diff against the incremental state.
- Curated exercise library and the four launch templates seeded.

---

## Phase 1 · Rivals & Logging (4 weeks)

**Ships:** signup, discovery, rivalry lifecycle, workout logger, the
head-to-head screen, feed with Realtime, taunts.

**Stories in scope.** A1–A5, B1–B4, C1, C2, F1.

**Order of work:**
1. Expo scaffold; expo-router; auth (Apple / Google / email).
2. Discovery + rivalry lifecycle. This is the smallest end-to-end
   surface — a user can sign up, find someone, and have a rivalry row.
3. Workout logger against `workouts` + `workout_sets`. Complete-workout
   button; PRs. Nothing offline yet.
4. Head-to-head screen wired to `head_to_head` view + Realtime.
5. Feed strip; taunts.
6. Push notifications for `workout_logged`, `lead_change`, `taunt`
   (F1 subset).

**Exit criteria:**
- Two testers on TestFlight can rival each other, log workouts, and see
  live updates on both phones.
- Paired Retention D7 (PRA D7) on the internal cohort ≥ 60 %.

**Deferred.** Challenges. Payments. HealthKit. Offline queue.

---

## Phase 2 · Challenges (3 weeks)

**Ships:** template catalogue, challenge creation, race view with live
splits, decision + rematch, weekly close-out.

**Stories in scope.** D1, D2, D3, D4, D6, F2.

**Order of work:**
1. Template catalogue screen against `challenge_templates` + steps. Free
   users see everything; Pro-gated cards show a locked affordance but
   render.
2. "Start a Challenge" flow (deadline picker + confirm) with the
   `challenge_instances` insert path.
3. Race view (`head_to_head_challenge`) with Realtime on
   `challenge_attempt_steps` + `challenge_attempts`.
4. `sweep-challenges` Edge Function scheduled via pg_cron.
5. `close-weekly` Edge Function; weekly-recap push.

**Exit criteria:**
- On the internal cohort, ≥ 35 % of active rivalries have run at least
  one challenge.
- Race view latency (my Start pressed → visible on rival's phone) < 3 s
  on a 4G connection.

---

## Phase 3 · Payments & Growth (3 weeks)

**Ships:** Stripe integration, paywall, invite links, HealthKit /
HealthConnect import.

**Stories in scope.** E1, E2, D5, A3 (invite links half), C3.

**Order of work:**
1. Stripe: `create-checkout-session`, `stripe-webhook`,
   `create-billing-portal`. Wire the entitlement banner in the app to
   `rf.has_pro`.
2. Paywall shown when a free user tries to start a Pro-gated challenge,
   with rival-name copy: "Ben unlocked this for you — you unlock the
   next one on Pro."
3. `create-invite` Edge Function + `rivalfit://invite/<code>` deep
   links; iMessage/WhatsApp OG cards.
4. HealthKit import for iOS, HealthConnect for Android, funnelled through
   `healthkit-sync` / `googlefit-sync` Edge Functions.
5. Proof attach on challenge attempts.

**Exit criteria:**
- Stripe webhook idempotency verified with a replay attack.
- End-to-end paid signup, cancellation, and reactivation observed.
- Test invite link opens the app cold-started and produces a pending
  rivalry.

---

## Phase 4 · Public launch (4 weeks)

**Ships:** offline logging, onboarding polish, notification granularity,
verified attempts, App Store submission.

**Stories in scope.** C4, D5 (verified path), C3 hardening, submission.

**Order of work:**
1. Offline workout logging with a local queue; conflict-free by
   client-generated UUIDs. Retry backoff.
2. Onboarding: single-question interstitial ("who is the friend you'll
   train against?"), Apple Contacts / phone-number invite.
3. Notification preferences per rivalry.
4. `verify-attempt` Edge Function (Phase 4 scope of D5).
5. Store screenshots, App Privacy manifest (only the data the schema
   actually stores), ATT prompt, TestFlight → production.

**Exit criteria:**
- Cold-launch to head-to-head render in < 2 s on a mid-range Android.
- App Store review passes on first submission, or with one round of
  clarification.
- 100 external beta users with PRA D30 ≥ 40 %.

---

## Post-launch experiments

Prioritised by expected lift on PRA / WAR, not by novelty:

- **Bracket view** (small crews). Cheap: it is a `GROUP BY` over
  existing rivalries. Unlocks the "gym clique" use case.
- **Rematch nudges.** Push to the loser ~24 h after a decided challenge:
  "want a rematch?" — pre-fills the deadline picker.
- **Streak rescue.** One "freeze" per month you can spend on a missed
  day. Deliberately expensive to implement well (it changes the streak
  math) so it lives here, not earlier.
- **Live cheer**. Wave a hand icon; brief haptic on the rival's phone.
  Post-launch experiment; ships behind a feature flag.
- **Duo plan** (E3). Two friends share Pro cheaper than two solos.
- **Community challenges.** A month-long benchmark everyone in the app
  can join; still one-vs-one, just against a rotating opponent.
- **Coach mode** (a coach can watch a set of rivalries). Only if PMF is
  clearly there — otherwise it is a distraction.

## What we are explicitly not doing

- **A public leaderboard.** Undermines the thesis (see PRD §3).
- **AI form check on video.** Too many failure modes for a launch;
  revisit only if a Pro user asks for it more than twice.
- **A social feed.** Every screen is *inside* a rivalry.
- **Cross-platform web parity.** A one-page marketing site is enough
  through Phase 4.
