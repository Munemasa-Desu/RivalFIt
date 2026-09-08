-- 0006 | Workouts and sets
--
-- A workout is a draft until it is completed. Everything downstream -- points,
-- streaks, scoreboards, PRs -- keys off the in_progress -> completed edge
-- (0008), which is the single moment a session becomes scoreable.

create table public.workouts (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles (id) on delete cascade,
  status         rf.workout_status not null default 'in_progress',
  source         rf.workout_source not null default 'manual',
  visibility     rf.visibility     not null default 'rivals',
  title          text,
  notes          text,

  started_at     timestamptz not null default now(),
  ended_at       timestamptz,
  duration_s     integer not null default 0,

  -- Trigger-maintained rollups of workout_sets.
  total_volume_kg  numeric(10,2) not null default 0,
  total_distance_m numeric(10,2) not null default 0,
  total_reps       integer       not null default 0,

  -- Trigger-maintained at completion.
  points           integer not null default 0,
  counts_for_score boolean not null default true,
  completed_at     timestamptz,

  external_id    text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint workouts_ends_after_start check (ended_at is null or ended_at >= started_at),
  constraint workouts_duration_nonneg  check (duration_s >= 0 and duration_s <= 86400),
  constraint workouts_notes_len        check (notes is null or length(notes) <= 2000),
  constraint workouts_completed_consistent
    check ((status = 'completed') = (completed_at is not null))
);

comment on column public.workouts.counts_for_score is
  'False when the session is past the per-day scoring cap. It still shows in the feed and in totals; it just cannot move the scoreboard.';

-- The scoreboard fan-out and the profile feed both scan by (user, time).
create index workouts_user_completed_idx
  on public.workouts (user_id, completed_at desc)
  where status = 'completed';

create index workouts_user_open_idx
  on public.workouts (user_id)
  where status = 'in_progress';

-- Idempotent imports from HealthKit / Google Fit.
create unique index workouts_external_id_idx
  on public.workouts (user_id, source, external_id)
  where external_id is not null;

create trigger workouts_touch_updated_at
  before update on public.workouts
  for each row execute function rf.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Sets
-- ---------------------------------------------------------------------------

create table public.workout_sets (
  id           uuid primary key default gen_random_uuid(),
  workout_id   uuid not null references public.workouts (id) on delete cascade,
  exercise_id  uuid not null references public.exercises (id) on delete restrict,
  set_index    integer not null,
  reps         integer,
  weight_kg    numeric(7,2),
  distance_m   numeric(10,2),
  duration_s   integer,
  rpe          numeric(3,1),
  is_warmup    boolean not null default false,
  completed_at timestamptz not null default now(),

  constraint workout_sets_unique_index unique (workout_id, set_index),
  constraint workout_sets_index_positive check (set_index >= 0),
  constraint workout_sets_reps_sane      check (reps      is null or reps      between 0 and 10000),
  constraint workout_sets_weight_sane    check (weight_kg is null or weight_kg between 0 and 1000),
  constraint workout_sets_distance_sane  check (distance_m is null or distance_m between 0 and 500000),
  constraint workout_sets_duration_sane  check (duration_s is null or duration_s between 0 and 86400),
  constraint workout_sets_rpe_sane       check (rpe is null or rpe between 1 and 10),
  constraint workout_sets_has_a_metric
    check (num_nonnulls(reps, weight_kg, distance_m, duration_s) > 0)
);

create index workout_sets_workout_idx  on public.workout_sets (workout_id, set_index);
create index workout_sets_exercise_idx on public.workout_sets (exercise_id, completed_at desc);

-- ---------------------------------------------------------------------------
-- Rollups
-- ---------------------------------------------------------------------------
-- Recomputed from scratch on every set change. A workout is tens of sets, so
-- the full re-aggregate is cheap and -- unlike incremental deltas -- cannot
-- drift after an edit or a delete.

create or replace function rf.recompute_workout_totals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_workout uuid := coalesce(new.workout_id, old.workout_id);
begin
  update public.workouts w
     set total_volume_kg = coalesce(agg.volume, 0),
         total_distance_m = coalesce(agg.distance, 0),
         total_reps       = coalesce(agg.reps, 0)
    from (
      select sum(
               case when s.is_warmup then 0
                    else coalesce(s.reps, 0) * coalesce(
                           s.weight_kg,
                           case when e.is_bodyweight
                                then coalesce(p.body_weight_kg, 70) * e.bodyweight_factor
                                else 0 end)
               end) as volume,
             sum(case when s.is_warmup then 0 else coalesce(s.distance_m, 0) end) as distance,
             sum(case when s.is_warmup then 0 else coalesce(s.reps, 0) end)       as reps
        from public.workout_sets s
        join public.exercises e on e.id = s.exercise_id
        join public.workouts  w2 on w2.id = s.workout_id
        join public.profiles  p  on p.id = w2.user_id
       where s.workout_id = v_workout
    ) agg
   where w.id = v_workout;

  return null;
end;
$$;

create trigger workout_sets_recompute_totals
  after insert or update or delete on public.workout_sets
  for each row execute function rf.recompute_workout_totals();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
-- Owner has full control. Rivals get read access to completed, rival-visible
-- sessions only -- a draft in progress is nobody else's business, and
-- `visibility = 'private'` is an escape hatch for a session you would rather
-- not have judged.

alter table public.workouts     enable row level security;
alter table public.workout_sets enable row level security;

create policy workouts_owner_all
  on public.workouts for all to authenticated
  using      (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy workouts_select_rival
  on public.workouts for select to authenticated
  using (
        status = 'completed'
    and visibility = 'rivals'
    and rf.shares_rivalry((select auth.uid()), user_id)
  );

create policy workout_sets_owner_all
  on public.workout_sets for all to authenticated
  using (exists (
    select 1 from public.workouts w
     where w.id = workout_sets.workout_id and w.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.workouts w
     where w.id = workout_sets.workout_id and w.user_id = (select auth.uid())
  ));

create policy workout_sets_select_rival
  on public.workout_sets for select to authenticated
  using (exists (
    select 1 from public.workouts w
     where w.id = workout_sets.workout_id
       and w.status = 'completed'
       and w.visibility = 'rivals'
       and rf.shares_rivalry((select auth.uid()), w.user_id)
  ));

grant select, insert, delete on public.workouts to authenticated;
-- points / counts_for_score / totals are trigger-owned.
grant update (status, source, visibility, title, notes, started_at, ended_at,
              duration_s, completed_at, external_id)
  on public.workouts to authenticated;
grant select, insert, update, delete on public.workout_sets to authenticated;
