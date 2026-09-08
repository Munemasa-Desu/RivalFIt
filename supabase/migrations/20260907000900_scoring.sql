-- 0009 | Scoreboards, streaks, PRs
--
-- The head-to-head screen must open instantly and update live. That rules out
-- aggregating workouts on read, so scores are maintained incrementally on
-- write and Realtime pushes the changed row.
--
-- One row per (rivalry, athlete, period) rather than a_/b_ column pairs: the
-- triggers then touch exactly one row and never branch on "am I user_a?", and
-- the head-to-head query is a self-join on rivalry_id.

create table public.rivalry_scores (
  rivalry_id     uuid not null references public.rivalries (id) on delete cascade,
  user_id        uuid not null references public.profiles (id) on delete cascade,
  period         rf.score_period not null,
  period_start   date not null,

  points         integer not null default 0,
  workouts       integer not null default 0,
  volume_kg      numeric(12,2) not null default 0,
  distance_m     numeric(12,2) not null default 0,
  duration_s     bigint  not null default 0,
  challenge_wins integer not null default 0,
  updated_at     timestamptz not null default now(),

  primary key (rivalry_id, user_id, period, period_start)
);

comment on table public.rivalry_scores is
  'Incrementally maintained scoreboard. Never write from the client; rf.recompute_rivalry_scores() is the repair path.';

create index rivalry_scores_current_idx
  on public.rivalry_scores (rivalry_id, period, period_start desc);

-- Closed weeks. This is what "you have taken 7 of the last 10" reads from.
create table public.rivalry_results (
  rivalry_id     uuid not null references public.rivalries (id) on delete cascade,
  period_start   date not null,
  winner_user_id uuid references public.profiles (id) on delete set null,
  points         jsonb not null default '{}'::jsonb,
  closed_at      timestamptz not null default now(),
  primary key (rivalry_id, period_start)
);

create table public.personal_records (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  metric      text not null,
  value       numeric(12,3) not null,
  workout_id  uuid references public.workouts (id) on delete set null,
  achieved_at timestamptz not null default now(),
  primary key (user_id, exercise_id, metric),
  constraint pr_metric_known check (metric in ('max_weight_kg', 'max_reps', 'max_distance_m', 'best_duration_s'))
);

-- ---------------------------------------------------------------------------
-- Completion: stamp the derived fields
-- ---------------------------------------------------------------------------

create or replace function rf.finalize_workout()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today_count integer;
  v_day         date;
  v_tz          text;
begin
  new.completed_at := coalesce(new.completed_at, now());
  new.ended_at     := coalesce(new.ended_at, new.completed_at);

  if new.duration_s = 0 then
    new.duration_s := greatest(0,
      least(86400, extract(epoch from (new.ended_at - new.started_at))::integer));
  end if;

  new.points := rf.compute_workout_points(
    new.duration_s, new.total_volume_kg, new.total_distance_m,
    new.source = 'challenge'
  );

  -- Anti-grind cap. Sessions past the third in a day still appear in the feed
  -- and in lifetime totals; they simply cannot move the scoreboard, which stops
  -- "log ten two-minute workouts" from being a winning strategy.
  select p.timezone into v_tz from public.profiles p where p.id = new.user_id;
  v_day := (new.completed_at at time zone coalesce(v_tz, 'UTC'))::date;

  select count(*) into v_today_count
    from public.workouts w
   where w.user_id = new.user_id
     and w.status = 'completed'
     and w.id <> new.id
     and (w.completed_at at time zone coalesce(v_tz, 'UTC'))::date = v_day;

  new.counts_for_score := v_today_count < 3;

  return new;
end;
$$;

create trigger workouts_finalize
  before update on public.workouts
  for each row
  when (new.status = 'completed' and old.status is distinct from 'completed')
  execute function rf.finalize_workout();

-- ---------------------------------------------------------------------------
-- Fan-out
-- ---------------------------------------------------------------------------

create or replace function rf.bump_rivalry_scores(
  p_user       uuid,
  p_at         timestamptz,
  p_points     integer,
  p_volume     numeric,
  p_distance   numeric,
  p_duration   integer,
  p_workouts   integer default 1,
  p_challenge_wins integer default 0
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rivalry uuid;
  v_period  rf.score_period;
begin
  for v_rivalry in
    select r.id from public.rivalries r
     where r.status = 'active' and p_user in (r.user_a, r.user_b)
  loop
    foreach v_period in array array['week', 'month', 'all_time']::rf.score_period[]
    loop
      insert into public.rivalry_scores as s
        (rivalry_id, user_id, period, period_start,
         points, workouts, volume_kg, distance_m, duration_s, challenge_wins)
      values
        (v_rivalry, p_user, v_period, rf.period_start(v_period, p_at),
         p_points, p_workouts, p_volume, p_distance, p_duration, p_challenge_wins)
      on conflict (rivalry_id, user_id, period, period_start) do update
        set points         = s.points         + excluded.points,
            workouts       = s.workouts       + excluded.workouts,
            volume_kg      = s.volume_kg      + excluded.volume_kg,
            distance_m     = s.distance_m     + excluded.distance_m,
            duration_s     = s.duration_s     + excluded.duration_s,
            challenge_wins = s.challenge_wins + excluded.challenge_wins,
            updated_at     = now();
    end loop;
  end loop;
end;
$$;

-- Who is ahead this week, before and after a change, so a lead flip can be
-- announced. This is the notification the whole product hangs on.
create or replace function rf.week_leader(p_rivalry uuid, p_at timestamptz)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.user_id
    from public.rivalry_scores s
   where s.rivalry_id = p_rivalry
     and s.period = 'week'
     and s.period_start = rf.period_start('week', p_at)
   order by s.points desc
   limit 1;
$$;

create or replace function rf.on_workout_completed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz        text;
  v_last_day  date;
  v_this_day  date;
  v_streak    integer;
  v_rivalry   record;
  v_before    uuid;
  v_after     uuid;
begin
  select p.timezone, (p.last_workout_at at time zone coalesce(p.timezone, 'UTC'))::date, p.current_streak
    into v_tz, v_last_day, v_streak
    from public.profiles p where p.id = new.user_id;

  v_this_day := (new.completed_at at time zone coalesce(v_tz, 'UTC'))::date;

  -- Streaks are day-based in the athlete's own timezone: a 05:00 session and a
  -- 23:00 session are the same day, and a traveller does not lose a streak to
  -- a flight.
  v_streak := case
    when v_last_day is null            then 1
    when v_last_day = v_this_day       then greatest(v_streak, 1)
    when v_last_day = v_this_day - 1   then v_streak + 1
    else 1
  end;

  update public.profiles p
     set total_workouts  = p.total_workouts + 1,
         points_all_time = p.points_all_time + case when new.counts_for_score then new.points else 0 end,
         current_streak  = v_streak,
         longest_streak  = greatest(p.longest_streak, v_streak),
         last_workout_at = greatest(coalesce(p.last_workout_at, new.completed_at), new.completed_at)
   where p.id = new.user_id;

  -- Personal records, one row per (exercise, metric). A workout with multiple
  -- sets against the same exercise (e.g. 5 x 5 back squat) would produce five
  -- candidate rows for the same (user, exercise, metric), which ON CONFLICT
  -- rejects. Pre-aggregate to the max per exercise inside this workout.
  insert into public.personal_records (user_id, exercise_id, metric, value, workout_id, achieved_at)
  select new.user_id, agg.exercise_id, agg.metric, agg.value, new.id, new.completed_at
    from (
      select s.exercise_id,
             m.metric,
             max(m.value) as value
        from public.workout_sets s
        cross join lateral (values
          ('max_weight_kg',   s.weight_kg),
          ('max_reps',        s.reps::numeric),
          ('max_distance_m',  s.distance_m),
          ('best_duration_s', s.duration_s::numeric)
        ) as m(metric, value)
       where s.workout_id = new.id
         and not s.is_warmup
         and m.value is not null
         and m.value > 0
       group by s.exercise_id, m.metric
    ) agg
  on conflict (user_id, exercise_id, metric) do update
    set value       = excluded.value,
        workout_id  = excluded.workout_id,
        achieved_at = excluded.achieved_at
    where excluded.value > public.personal_records.value;

  if not new.counts_for_score then
    return null;
  end if;

  -- Snapshot the leader per rivalry, apply the workout, then look again.
  for v_rivalry in
    select r.id from public.rivalries r
     where r.status = 'active' and new.user_id in (r.user_a, r.user_b)
  loop
    v_before := rf.week_leader(v_rivalry.id, new.completed_at);

    perform rf.emit_event(
      v_rivalry.id, new.user_id, 'workout_logged', 'workout', new.id,
      jsonb_build_object('points', new.points, 'title', new.title,
                         'duration_s', new.duration_s)
    );
  end loop;

  perform rf.bump_rivalry_scores(
    new.user_id, new.completed_at, new.points,
    new.total_volume_kg, new.total_distance_m, new.duration_s
  );

  for v_rivalry in
    select r.id from public.rivalries r
     where r.status = 'active' and new.user_id in (r.user_a, r.user_b)
  loop
    v_after := rf.week_leader(v_rivalry.id, new.completed_at);
    if v_after = new.user_id and v_after is distinct from rf.rival_of(v_rivalry.id, new.user_id) then
      -- Only announce when this workout is what put them in front.
      if not exists (
        select 1 from public.rivalry_events e
         where e.rivalry_id = v_rivalry.id
           and e.kind = 'lead_change'
           and e.actor_id = new.user_id
           and e.created_at > date_trunc('week', new.completed_at at time zone 'UTC')
           and e.created_at > coalesce((
             select max(e2.created_at) from public.rivalry_events e2
              where e2.rivalry_id = v_rivalry.id and e2.kind = 'lead_change'
                and e2.actor_id is distinct from new.user_id
           ), '-infinity'::timestamptz)
      ) then
        perform rf.emit_event(
          v_rivalry.id, new.user_id, 'lead_change', 'workout', new.id,
          jsonb_build_object('period', 'week')
        );
      end if;
    end if;
  end loop;

  return null;
end;
$$;

create trigger workouts_on_completed
  after update on public.workouts
  for each row
  when (new.status = 'completed' and old.status is distinct from 'completed')
  execute function rf.on_workout_completed();

-- ---------------------------------------------------------------------------
-- Challenge wins feed the scoreboard
-- ---------------------------------------------------------------------------

create or replace function rf.on_challenge_decided()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.winner_user_id is null then
    return null;
  end if;

  perform rf.bump_rivalry_scores(
    new.winner_user_id, coalesce(new.decided_at, now()),
    25,          -- winning a head-to-head is worth more than a solo session
    0, 0, 0,
    0,           -- not a workout
    1            -- challenge win
  );

  return null;
end;
$$;

create trigger ci_on_decided
  after update of state on public.challenge_instances
  for each row
  when (new.state = 'decided' and old.state is distinct from 'decided')
  execute function rf.on_challenge_decided();

-- ---------------------------------------------------------------------------
-- Repair and close-out
-- ---------------------------------------------------------------------------
-- Incremental counters drift eventually -- an edited workout, a bad deploy, a
-- restored backup. This rebuilds one rivalry's scoreboard from source rows and
-- is safe to run at any time.

create or replace function rf.recompute_rivalry_scores(p_rivalry uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.rivalry_scores where rivalry_id = p_rivalry;

  insert into public.rivalry_scores
    (rivalry_id, user_id, period, period_start,
     points, workouts, volume_kg, distance_m, duration_s, challenge_wins)
  select p_rivalry,
         w.user_id,
         pr.period,
         rf.period_start(pr.period, w.completed_at),
         sum(w.points),
         count(*),
         sum(w.total_volume_kg),
         sum(w.total_distance_m),
         sum(w.duration_s),
         0
    from public.rivalries r
    join public.workouts w
      on w.user_id in (r.user_a, r.user_b)
     and w.status = 'completed'
     and w.counts_for_score
     and w.completed_at >= coalesce(r.accepted_at, r.created_at)
    cross join unnest(array['week', 'month', 'all_time']::rf.score_period[]) as pr(period)
   where r.id = p_rivalry
   group by w.user_id, pr.period, rf.period_start(pr.period, w.completed_at);

  -- Fold challenge wins back in.
  insert into public.rivalry_scores as s
    (rivalry_id, user_id, period, period_start, points, workouts, challenge_wins)
  select p_rivalry, i.winner_user_id, pr.period,
         rf.period_start(pr.period, i.decided_at),
         25 * count(*), 0, count(*)
    from public.challenge_instances i
    cross join unnest(array['week', 'month', 'all_time']::rf.score_period[]) as pr(period)
   where i.rivalry_id = p_rivalry
     and i.state = 'decided'
     and i.winner_user_id is not null
   group by i.winner_user_id, pr.period, rf.period_start(pr.period, i.decided_at)
  on conflict (rivalry_id, user_id, period, period_start) do update
    set points         = s.points + excluded.points,
        challenge_wins = s.challenge_wins + excluded.challenge_wins,
        updated_at     = now();
end;
$$;

-- Closes every week that ended before now and has not been recorded. Run from
-- pg_cron shortly after the UTC week boundary.
create or replace function rf.close_finished_weeks()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row   record;
  v_count integer := 0;
begin
  for v_row in
    select s.rivalry_id,
           s.period_start,
           jsonb_object_agg(s.user_id::text, s.points) as points,
           (array_agg(s.user_id order by s.points desc))[1] as top_user,
           max(s.points) as top_points,
           count(*) filter (where s.points = max(s.points) over ()) as _unused
      from public.rivalry_scores s
     where s.period = 'week'
       and s.period_start + 7 <= (now() at time zone 'UTC')::date
       and not exists (
         select 1 from public.rivalry_results rr
          where rr.rivalry_id = s.rivalry_id and rr.period_start = s.period_start
       )
     group by s.rivalry_id, s.period_start
  loop
    insert into public.rivalry_results (rivalry_id, period_start, winner_user_id, points)
    values (
      v_row.rivalry_id,
      v_row.period_start,
      case when (select count(distinct value) from jsonb_each_text(v_row.points)) = 1
           then null                       -- draw
           else v_row.top_user end,
      v_row.points
    )
    on conflict (rivalry_id, period_start) do nothing;

    perform rf.emit_event(
      v_row.rivalry_id, null, 'period_closed', 'rivalry_result', null,
      jsonb_build_object('period_start', v_row.period_start, 'points', v_row.points)
    );

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke execute on function
  rf.bump_rivalry_scores(uuid, timestamptz, integer, numeric, numeric, integer, integer, integer),
  rf.recompute_rivalry_scores(uuid),
  rf.close_finished_weeks()
from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.rivalry_scores   enable row level security;
alter table public.rivalry_results  enable row level security;
alter table public.personal_records enable row level security;

create policy rivalry_scores_select_participant
  on public.rivalry_scores for select to authenticated
  using (rf.is_rivalry_member(rivalry_id, (select auth.uid())));

create policy rivalry_results_select_participant
  on public.rivalry_results for select to authenticated
  using (rf.is_rivalry_member(rivalry_id, (select auth.uid())));

create policy pr_select_self
  on public.personal_records for select to authenticated
  using (user_id = (select auth.uid()));

create policy pr_select_rival
  on public.personal_records for select to authenticated
  using (rf.shares_rivalry((select auth.uid()), user_id));

-- Read-only for clients across the board: every write here is a trigger's.
grant select on public.rivalry_scores, public.rivalry_results, public.personal_records
  to authenticated;
