-- 0002 | The `rf` schema: enums, generic helpers, scoring math.
--
-- Everything that is not directly exposed to PostgREST lives in `rf`.
-- `public` holds only the tables/views the client is allowed to see.
--
-- SECURITY DEFINER functions all pin `search_path = ''` and fully qualify every
-- object, so a caller cannot shadow a name and hijack the elevated context.

create schema if not exists rf;
grant usage on schema rf to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type rf.rivalry_status as enum ('pending', 'active', 'paused', 'declined', 'ended');
create type rf.unit_system    as enum ('metric', 'imperial');
create type rf.workout_status as enum ('in_progress', 'completed', 'discarded');
create type rf.workout_source as enum ('manual', 'challenge', 'healthkit', 'google_fit', 'import');
create type rf.visibility     as enum ('rivals', 'private');

create type rf.exercise_modality as enum
  ('strength', 'cardio', 'bodyweight', 'carry', 'machine', 'mobility');

create type rf.challenge_category as enum
  ('hyrox', 'tactical', 'benchmark', 'hiit', 'endurance', 'strength', 'community');

-- Which direction is "better" for a challenge result.
create type rf.scoring_type as enum
  ('time_asc', 'reps_desc', 'load_desc', 'distance_desc', 'points_desc');

create type rf.challenge_state as enum ('open', 'live', 'decided', 'expired', 'cancelled');
create type rf.attempt_state   as enum ('not_started', 'in_progress', 'completed', 'dnf', 'abandoned');

create type rf.score_period as enum ('week', 'month', 'all_time');

create type rf.event_kind as enum (
  'rivalry_started', 'workout_logged', 'pr_set', 'lead_change',
  'challenge_created', 'challenge_started', 'challenge_completed',
  'challenge_decided', 'period_closed', 'streak_milestone', 'taunt'
);

create type rf.plan_tier as enum ('free', 'pro');

-- ---------------------------------------------------------------------------
-- Generic helpers
-- ---------------------------------------------------------------------------

create or replace function rf.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Scoreboards are bucketed in UTC. Every rollup goes through these two so the
-- app, the triggers and the weekly close job can never disagree on a boundary.
create or replace function rf.period_start(p_period rf.score_period, p_at timestamptz)
returns date
language sql
immutable
as $$
  select case p_period
    when 'week'     then (date_trunc('week',  p_at at time zone 'UTC'))::date
    when 'month'    then (date_trunc('month', p_at at time zone 'UTC'))::date
    when 'all_time' then '1970-01-01'::date
  end;
$$;

create or replace function rf.period_end(p_period rf.score_period, p_start date)
returns date
language sql
immutable
as $$
  select case p_period
    when 'week'     then p_start + 7
    when 'month'    then (p_start + interval '1 month')::date
    when 'all_time' then '9999-12-31'::date
  end;
$$;

-- ---------------------------------------------------------------------------
-- Scoring
-- ---------------------------------------------------------------------------
-- One formula, one place. The client renders points but never computes them:
-- the value written to `workouts.points` is always the trigger's, so two
-- rivals on different app versions cannot score the same session differently.
--
-- Shape: showing up is worth the most per unit of effort, and every input
-- saturates. A 3-hour session cannot bury a rival who trained honestly for 45
-- minutes, which is what keeps an always-on scoreboard from becoming a
-- volume-dumping contest.
create or replace function rf.compute_workout_points(
  p_duration_s   integer,
  p_volume_kg    numeric,
  p_distance_m   numeric,
  p_challenge    boolean default false
)
returns integer
language sql
immutable
as $$
  select greatest(0, least(150, round(
      10                                                              -- turned up
    + least(coalesce(p_duration_s, 0) / 60.0, 90) * 0.5               -- <= 45
    + least(coalesce(p_volume_kg, 0)  / 500.0,  20)                   -- <= 20
    + least(coalesce(p_distance_m, 0) / 200.0,  25)                   -- <= 25
    + case when p_challenge then 15 else 0 end                        -- head-to-head bonus
  )))::integer;
$$;

comment on function rf.compute_workout_points is
  'Canonical point value of a finished workout. Saturating by design: see docs/02-DATA-MODEL.md.';
