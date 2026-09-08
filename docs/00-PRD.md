# RivalFit — Product Requirements Document

*v0.1 · September 2026 · Owner: Founding team*

---

## 1. Elevator pitch

RivalFit turns fitness into a **rolling head-to-head with the friends you
already train around**. There are no competitions to set up, no groups to
manage, no leaderboards to opt into. You add a rival, and from that moment
a live scoreboard exists between the two of you — this week's points, this
month's, all time, plus the record of every week either of you has won.
When you want to escalate, you launch a **pre-built challenge** — Hyrox
Simulation, Tactical Fitness Test, "Cindy" AMRAP, Powerlifting Total — and
race your rival through the same script.

## 2. Problem

Strava, Whoop, Apple Fitness+, and every mainstream fitness app treat social
as an **afterthought layer** — a feed of kudos on top of a solo tracker.
The apps that *are* social (Ladder, Future) sell a coach, not a rival.
Nothing on the market is built around the **specific dynamic that actually
makes people show up**: another person who will notice if you don't.

Two things are missing:

- **Persistent friction-free rivalry.** Competitions require a start date,
  a name, invitees, a metric, a duration. Nobody sets one up on a Tuesday.
- **Ready-to-run head-to-head formats.** "Do a Hyrox with me" is a whole
  planning conversation. It should be a two-tap invitation.

## 3. Thesis

- **The rivalry is the unit of engagement**, not the workout or the group.
- **Setup is the enemy.** The scoreboard must exist the moment two users
  become rivals, with no configuration.
- **Formats travel further than freeform.** A named, embedded challenge
  ("Cindy", "Hyrox") is easier to invite into than a blank workout invite.
- **Payment gate: intensity, not access.** Free users can rival anyone,
  log anything, and *browse* the challenge catalogue. Pro (~$7.99/mo,
  $59/yr) unlocks starting premium challenges and asymmetric power-ups
  (extra rivals, historical week comparisons, verified proof-of-workout).

## 4. Target user

**Primary — "the training pair."** Two friends, 22–40, who already train
enough that they text each other about it. Weightlifting, Hyrox, tactical /
prep community, CrossFit-adjacent. On-ramp: the more competitive of the two
brings the other.

**Secondary — "the small crew."** 3–8 friends from a gym, unit, or team
who want a persistent bracket. Rivalries fan out, but each screen is still
one-vs-one.

## 5. The two differentiating screens

### 5.1 Head-to-Head View (`head_to_head`)

The screen the app opens to when there is at least one active rivalry.
No configuration. Renders from a single query
([`public.head_to_head`](../supabase/migrations/20260907001000_views.sql)).

Layout, top to bottom:

1. **Two avatar-scoped columns**, "me" on the left and the rival on the
   right, each with handle, current streak, and this week's point total in
   a large monospaced numeral.
2. **The bar** — a single horizontal split whose split point is
   `me_week_points / (me + them)`. This is the "you are behind" cue that
   drives return visits.
3. **Comparison rows** — workouts, volume (kg), distance (m), duration (h:mm),
   challenge wins. Each row highlights whichever side is ahead this week.
4. **Head-to-head record** — "You: 4 · Ben: 6" over the last 10 closed
   weeks, from `public.rivalry_results`.
5. **Recent feed** — the last 10 events from `public.rivalry_feed`
   (workouts, PRs, lead changes, challenges, taunts) as a live-updating
   list via Supabase Realtime.
6. **Call-to-action** — one primary button, "Challenge Ben", which opens
   the template picker (5.2).

### 5.2 Challenge templates & race view

**Template picker.** A card grid grouped by category (Hyrox · Tactical ·
Benchmark · HIIT · Endurance · Strength). Each card shows icon, name,
one-line subtitle, difficulty (1–5), estimated duration, equipment list,
and a Pro lock icon if `requires_pro = true`. The catalogue is browsable
by every user; only *starting* a Pro race requires Pro.

**Race view (`head_to_head_challenge`).** Two lanes, live splits.
- Left lane: your name, elapsed time, current station number, live score
  in the template's unit.
- Right lane: your rival's same values, updated by Realtime.
- Middle: the current step ("Wall Balls · 100 reps") with the live gap
  between you.
- Bottom: sequential station splits stacked below each lane so the
  history of the race is a scannable pair of columns.

Winner determination is server-side ([`rf.decide_challenge`](../supabase/migrations/20260907000800_challenges.sql)):
both finish → better score wins; one finishes and the other times out →
the finisher wins; neither finishes → expired (no win, no loss).

## 6. Non-goals for the MVP

- **Freeform group leaderboards** — brackets can be inferred later from a
  set of pairwise rivalries; a bracket object is not on the critical path.
- **Coaching / training plans** — RivalFit is not a coach and does not
  prescribe.
- **Nutrition, sleep, HRV** — Whoop and Oura already own that. We may read
  their exports later; we do not compete on that ground.
- **Live video / cheer** — post-launch experiment for the race view.
- **Public feed** — nothing is world-visible; the feed lives inside the
  rivalry.

## 7. Success metrics

Product-level KPIs, tracked from day one:

- **PRA — Paired Retention D7 / D30.** Percentage of *rivalry pairs* where
  both users log at least one workout in the target window. This is the
  real product metric — a single-user D7 misses the whole thesis.
- **Weekly Active Rivalries (WAR).** Rivalries with a lead change in the
  last 7 days.
- **Challenge Start Rate.** Rivalries that run at least one challenge in
  their first 14 days. Target: 35 % pre-launch, 55 % post-Phase-3.
- **Solo→Rival Conversion.** Solo signups (no rival within 24 h of
  onboarding) that gain a rival within 7 days. Push notifications gate.
- **Pro Conversion.** Free users who upgrade after being asked to start a
  Pro-gated race by their rival. This is the top of the paid funnel —
  see 3.
- **Taunt & Feed Interaction Rate.** Events per active rivalry per week.
  A leading indicator for PRA.

## 8. Constraints & tenets

- **iOS and Android from day one** (Expo). No web app in MVP.
- **Offline-first for workout logging.** A user in a garage gym with bad
  reception must be able to log sets. Sync when connected.
- **Server clock owns time.** A phone with a bent clock cannot steal a
  challenge win — the race trigger derives `elapsed_s` from server
  `started_at`/`completed_at` and only accepts a client value when there is
  no server-recorded start (offline attempts), leaving that attempt marked
  `verified = false`.
- **RLS is the API.** Every table has RLS on. Direct-from-client access
  is only safe because the schema itself enforces the rules — see
  `docs/03-API-ARCHITECTURE.md`.
- **No dark patterns around streaks.** Streaks live in the athlete's
  timezone (0009), so a traveller does not lose one to a flight. A day
  with three workouts still scores three (up to the anti-grind cap); we do
  not fake urgency.
