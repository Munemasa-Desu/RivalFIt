-- 0008 | Challenge templates and head-to-head races
--
-- Four levels, and the split matters:
--
--   challenge_templates       the recipe ("Hyrox Simulation")
--   challenge_template_steps  the exercises baked into it, in order
--   challenge_instances       one rivalry racing one template, once
--   challenge_attempts        one athlete's run at that instance
--   challenge_attempt_steps   per-station splits, which is what makes the
--                             side-by-side race readable while it is live
--
-- Templates are versioned and immutable once published: an instance pins
-- `template_version`, so a recipe edit can never retroactively change what two
-- people already raced.

-- ---------------------------------------------------------------------------
-- Templates
-- ---------------------------------------------------------------------------

create table public.challenge_templates (
  id                 uuid primary key default gen_random_uuid(),
  slug               text not null,
  version            integer not null default 1,
  name               text not null,
  subtitle           text,
  description        text,
  category           rf.challenge_category not null,
  scoring_type       rf.scoring_type not null,
  score_unit         text not null default 'seconds',

  time_cap_s         integer,
  estimated_duration_s integer,
  difficulty         smallint not null default 3,
  equipment          text[] not null default '{}',
  rounds             smallint not null default 1,

  icon               text,
  hero_image_url     text,
  requires_pro       boolean not null default false,
  created_by         uuid references public.profiles (id) on delete cascade,
  published_at       timestamptz,
  created_at         timestamptz not null default now(),

  constraint challenge_templates_slug_version unique (slug, version),
  constraint challenge_templates_slug_format check (slug ~ '^[a-z0-9_]{2,60}$'),
  constraint challenge_templates_difficulty  check (difficulty between 1 and 5),
  constraint challenge_templates_rounds      check (rounds between 1 and 50),
  constraint challenge_templates_cap_sane    check (time_cap_s is null or time_cap_s between 60 and 43200)
);

comment on column public.challenge_templates.requires_pro is
  'Gates instance creation, not visibility. Free users see the whole catalogue -- that is the upgrade prompt -- and a Pro creator unlocks the race for their free rival.';

create index challenge_templates_category_idx
  on public.challenge_templates (category, difficulty)
  where published_at is not null;

-- ---------------------------------------------------------------------------
-- Template steps: the embedded exercises
-- ---------------------------------------------------------------------------
-- `block_index` groups steps into a repeatable unit. Hyrox is 8 blocks of
-- [1 km run, station]; a strength benchmark is one block. The player walks
-- steps in (block_index, step_index) order.

create table public.challenge_template_steps (
  id              uuid primary key default gen_random_uuid(),
  template_id     uuid not null references public.challenge_templates (id) on delete cascade,
  block_index     smallint not null default 0,
  step_index      smallint not null,
  exercise_id     uuid not null references public.exercises (id) on delete restrict,
  label           text,

  target_reps       integer,
  target_distance_m numeric(10,2),
  target_weight_kg  numeric(7,2),
  target_duration_s integer,
  rest_after_s      integer not null default 0,
  notes             text,

  constraint cts_unique_position unique (template_id, block_index, step_index),
  constraint cts_has_a_target
    check (num_nonnulls(target_reps, target_distance_m, target_weight_kg, target_duration_s) > 0),
  constraint cts_rest_sane check (rest_after_s between 0 and 3600)
);

create index cts_template_order_idx
  on public.challenge_template_steps (template_id, block_index, step_index);

-- A published template is frozen. Editing means publishing version + 1.
create or replace function rf.freeze_published_template()
returns trigger
language plpgsql
as $$
declare
  v_published timestamptz;
  v_template  uuid := coalesce(new.template_id, old.template_id);
begin
  select t.published_at into v_published
    from public.challenge_templates t where t.id = v_template;

  if v_published is not null then
    raise exception 'template % is published and immutable; publish a new version instead', v_template
      using errcode = 'check_violation';
  end if;

  return coalesce(new, old);
end;
$$;

create trigger cts_freeze_published
  before insert or update or delete on public.challenge_template_steps
  for each row execute function rf.freeze_published_template();

-- ---------------------------------------------------------------------------
-- Instances: one rivalry racing one template
-- ---------------------------------------------------------------------------

create table public.challenge_instances (
  id               uuid primary key default gen_random_uuid(),
  rivalry_id       uuid not null references public.rivalries (id) on delete cascade,
  template_id      uuid not null references public.challenge_templates (id) on delete restrict,
  template_version integer not null,
  created_by       uuid not null references public.profiles (id) on delete cascade,
  state            rf.challenge_state not null default 'open',
  opens_at         timestamptz not null default now(),
  deadline         timestamptz not null,
  winner_user_id   uuid references public.profiles (id) on delete set null,
  decided_at       timestamptz,
  decision_reason  text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint ci_deadline_after_open check (deadline > opens_at),
  constraint ci_decided_consistent
    check ((state in ('decided', 'expired')) = (decided_at is not null))
);

-- One live race per template per rivalry. Rematches are allowed only once the
-- previous one is off the board, which keeps the rivalry screen unambiguous.
create unique index ci_one_open_per_template_idx
  on public.challenge_instances (rivalry_id, template_id)
  where state in ('open', 'live');

create index ci_rivalry_idx  on public.challenge_instances (rivalry_id, created_at desc);
create index ci_deadline_idx on public.challenge_instances (deadline)
  where state in ('open', 'live');

create trigger ci_touch_updated_at
  before update on public.challenge_instances
  for each row execute function rf.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Attempts
-- ---------------------------------------------------------------------------

create table public.challenge_attempts (
  id           uuid primary key default gen_random_uuid(),
  instance_id  uuid not null references public.challenge_instances (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  state        rf.attempt_state not null default 'not_started',
  started_at   timestamptz,
  completed_at timestamptz,
  elapsed_s    integer,
  score        numeric(12,3),
  score_unit   text,
  workout_id   uuid references public.workouts (id) on delete set null,
  proof_url    text,
  verified     boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint ca_one_per_user unique (instance_id, user_id),
  constraint ca_elapsed_sane check (elapsed_s is null or elapsed_s between 0 and 86400),
  constraint ca_completed_has_score
    check (state <> 'completed' or (completed_at is not null and score is not null))
);

create index ca_user_idx on public.challenge_attempts (user_id, created_at desc);

create trigger ca_touch_updated_at
  before update on public.challenge_attempts
  for each row execute function rf.touch_updated_at();

create table public.challenge_attempt_steps (
  id           uuid primary key default gen_random_uuid(),
  attempt_id   uuid not null references public.challenge_attempts (id) on delete cascade,
  step_id      uuid not null references public.challenge_template_steps (id) on delete restrict,
  split_s      integer not null,
  reps_done    integer,
  weight_kg    numeric(7,2),
  distance_m   numeric(10,2),
  duration_s   integer,
  completed_at timestamptz not null default now(),

  constraint cas_unique_step unique (attempt_id, step_id),
  constraint cas_split_sane check (split_s between 0 and 86400)
);

comment on column public.challenge_attempt_steps.split_s is
  'Cumulative elapsed seconds at the moment this step finished. Two attempts joined on step_id give the live gap between rivals, station by station.';

create index cas_attempt_idx on public.challenge_attempt_steps (attempt_id, split_s);

-- ---------------------------------------------------------------------------
-- Scoring direction
-- ---------------------------------------------------------------------------

create or replace function rf.score_is_better(p_type rf.scoring_type, p_a numeric, p_b numeric)
returns boolean
language sql
immutable
as $$
  select case
    when p_a is null then false
    when p_b is null then true
    when p_type = 'time_asc' then p_a < p_b
    else p_a > p_b
  end;
$$;

-- Derive the comparable number for an attempt from the template's scoring rule,
-- so an athlete can never submit a score the movement data does not support.
create or replace function rf.derive_attempt_score(p_attempt uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_type    rf.scoring_type;
  v_elapsed integer;
  v_workout uuid;
  v_score   numeric;
begin
  select t.scoring_type, a.elapsed_s, a.workout_id
    into v_type, v_elapsed, v_workout
    from public.challenge_attempts a
    join public.challenge_instances i on i.id = a.instance_id
    join public.challenge_templates t on t.id = i.template_id
   where a.id = p_attempt;

  if v_type is null then
    return null;
  end if;

  case v_type
    when 'time_asc' then
      v_score := v_elapsed;
    when 'reps_desc' then
      select coalesce(sum(s.reps_done), 0) into v_score
        from public.challenge_attempt_steps s where s.attempt_id = p_attempt;
    when 'load_desc' then
      select max(s.weight_kg) into v_score
        from public.challenge_attempt_steps s where s.attempt_id = p_attempt;
    when 'distance_desc' then
      select coalesce(sum(s.distance_m), 0) into v_score
        from public.challenge_attempt_steps s where s.attempt_id = p_attempt;
    when 'points_desc' then
      select w.points into v_score
        from public.workouts w where w.id = v_workout;
  end case;

  return v_score;
end;
$$;

-- ---------------------------------------------------------------------------
-- Instance lifecycle
-- ---------------------------------------------------------------------------

create or replace function rf.prepare_challenge_instance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status   rf.rivalry_status;
  v_pro      boolean;
  v_version  integer;
  v_a        uuid;
  v_b        uuid;
begin
  select r.status, r.user_a, r.user_b into v_status, v_a, v_b
    from public.rivalries r where r.id = new.rivalry_id;

  if v_status is distinct from 'active' then
    raise exception 'challenges require an active rivalry' using errcode = 'check_violation';
  end if;

  if new.created_by not in (v_a, v_b) then
    raise exception 'only a member of the rivalry can start a challenge'
      using errcode = 'insufficient_privilege';
  end if;

  select t.version, t.requires_pro into v_version, v_pro
    from public.challenge_templates t
   where t.id = new.template_id and t.published_at is not null;

  if v_version is null then
    raise exception 'template is not published' using errcode = 'check_violation';
  end if;

  -- One Pro subscriber unlocks the race for the pair. That asymmetry is the
  -- point: the paying user brings their rival along, and the free rival meets
  -- the paywall the next time they want to start one themselves.
  if v_pro and not rf.has_pro(new.created_by) then
    raise exception 'this challenge requires RivalFit Pro' using errcode = 'insufficient_privilege';
  end if;

  new.template_version := v_version;
  return new;
end;
$$;

create trigger ci_prepare
  before insert on public.challenge_instances
  for each row execute function rf.prepare_challenge_instance();

-- Both athletes get an attempt row up front, so the side-by-side race view
-- always has two lanes to render -- even before anyone has pressed start.
create or replace function rf.seed_challenge_attempts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_a uuid;
  v_b uuid;
begin
  select r.user_a, r.user_b into v_a, v_b
    from public.rivalries r where r.id = new.rivalry_id;

  insert into public.challenge_attempts (instance_id, user_id)
  values (new.id, v_a), (new.id, v_b);

  perform rf.emit_event(
    new.rivalry_id, new.created_by, 'challenge_created', 'challenge_instance', new.id,
    jsonb_build_object('template_id', new.template_id, 'deadline', new.deadline)
  );

  return null;
end;
$$;

create trigger ci_seed_attempts
  after insert on public.challenge_instances
  for each row execute function rf.seed_challenge_attempts();

-- ---------------------------------------------------------------------------
-- Attempt lifecycle
-- ---------------------------------------------------------------------------

create or replace function rf.guard_attempt_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state rf.challenge_state;
  v_rivalry uuid;
begin
  if new.user_id is distinct from old.user_id
     or new.instance_id is distinct from old.instance_id then
    raise exception 'attempt ownership is immutable' using errcode = 'check_violation';
  end if;

  select i.state, i.rivalry_id into v_state, v_rivalry
    from public.challenge_instances i where i.id = new.instance_id;

  if v_state not in ('open', 'live') and new.state is distinct from old.state then
    raise exception 'this challenge is closed' using errcode = 'check_violation';
  end if;

  if new.state = old.state then
    return new;
  end if;

  case
    when old.state = 'not_started' and new.state = 'in_progress' then
      new.started_at := coalesce(new.started_at, now());

    when old.state = 'in_progress' and new.state = 'completed' then
      new.completed_at := coalesce(new.completed_at, now());
      -- Server clock wins. The client may supply elapsed_s only when there is
      -- no server-recorded start (offline / imported attempts), and such an
      -- attempt stays `verified = false`.
      new.elapsed_s := case
        when new.started_at is not null
          then greatest(0, extract(epoch from (new.completed_at - new.started_at))::integer)
        else new.elapsed_s
      end;

    when old.state = 'in_progress' and new.state in ('dnf', 'abandoned') then
      new.completed_at := coalesce(new.completed_at, now());

    when old.state = 'not_started' and new.state = 'abandoned' then
      null;

    else
      raise exception 'illegal attempt transition: % -> %', old.state, new.state
        using errcode = 'check_violation';
  end case;

  return new;
end;
$$;

create trigger ca_guard_transition
  before update on public.challenge_attempts
  for each row execute function rf.guard_attempt_transition();

-- Scores are derived, never trusted from the client.
-- Compute the derived score from NEW rather than re-selecting the attempt row.
-- This trigger is BEFORE UPDATE, so a re-select would return the pre-update
-- row and elapsed_s would still be null. Step totals do come from a sibling
-- table (challenge_attempt_steps) which is committed by this point, and
-- workouts.points is likewise a completed sibling read.
create or replace function rf.stamp_attempt_score()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type rf.scoring_type;
  v_unit text;
  v_val  numeric;
begin
  select t.scoring_type, t.score_unit into v_type, v_unit
    from public.challenge_instances i
    join public.challenge_templates t on t.id = i.template_id
   where i.id = new.instance_id;

  case v_type
    when 'time_asc' then
      v_val := new.elapsed_s;
    when 'reps_desc' then
      select coalesce(sum(s.reps_done), 0) into v_val
        from public.challenge_attempt_steps s where s.attempt_id = new.id;
    when 'load_desc' then
      select max(s.weight_kg) into v_val
        from public.challenge_attempt_steps s where s.attempt_id = new.id;
    when 'distance_desc' then
      select coalesce(sum(s.distance_m), 0) into v_val
        from public.challenge_attempt_steps s where s.attempt_id = new.id;
    when 'points_desc' then
      select w.points into v_val
        from public.workouts w where w.id = new.workout_id;
  end case;

  new.score      := v_val;
  new.score_unit := v_unit;
  return new;
end;
$$;

-- Runs after the guard so it sees the stamped elapsed_s.
create trigger ca_stamp_score
  before update on public.challenge_attempts
  for each row
  when (new.state = 'completed')
  execute function rf.stamp_attempt_score();

create or replace function rf.on_attempt_state_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rivalry uuid;
begin
  select i.rivalry_id into v_rivalry
    from public.challenge_instances i where i.id = new.instance_id;

  if new.state = 'in_progress' and old.state = 'not_started' then
    update public.challenge_instances
       set state = 'live'
     where id = new.instance_id and state = 'open';

    perform rf.emit_event(v_rivalry, new.user_id, 'challenge_started',
      'challenge_attempt', new.id, jsonb_build_object('instance_id', new.instance_id));

  elsif new.state in ('completed', 'dnf', 'abandoned') then
    perform rf.emit_event(v_rivalry, new.user_id, 'challenge_completed',
      'challenge_attempt', new.id,
      jsonb_build_object('instance_id', new.instance_id, 'score', new.score, 'state', new.state));

    perform rf.decide_challenge(new.instance_id);
  end if;

  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Deciding a race
-- ---------------------------------------------------------------------------
-- Called on every terminal attempt and by the deadline sweeper. Idempotent and
-- self-guarding: it takes a row lock and no-ops if the instance already closed.

create or replace function rf.decide_challenge(p_instance uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inst    public.challenge_instances%rowtype;
  v_type    rf.scoring_type;
  v_a       public.challenge_attempts%rowtype;
  v_b       public.challenge_attempts%rowtype;
  v_winner  uuid;
  v_reason  text;
  v_state   rf.challenge_state;
  v_a_done  boolean;
  v_b_done  boolean;
begin
  select * into v_inst from public.challenge_instances
   where id = p_instance for update;

  if not found or v_inst.state not in ('open', 'live') then
    return;
  end if;

  select t.scoring_type into v_type
    from public.challenge_templates t where t.id = v_inst.template_id;

  select * into v_a from public.challenge_attempts a
   where a.instance_id = p_instance
   order by a.user_id limit 1;

  select * into v_b from public.challenge_attempts a
   where a.instance_id = p_instance
   order by a.user_id desc limit 1;

  -- Wait for both athletes unless the clock has run out.
  if not (v_a.state in ('completed', 'dnf', 'abandoned')
      and v_b.state in ('completed', 'dnf', 'abandoned'))
     and now() < v_inst.deadline then
    return;
  end if;

  v_a_done := v_a.state = 'completed';
  v_b_done := v_b.state = 'completed';

  if v_a_done and v_b_done then
    v_state := 'decided';
    if rf.score_is_better(v_type, v_a.score, v_b.score) then
      v_winner := v_a.user_id; v_reason := 'better_score';
    elsif rf.score_is_better(v_type, v_b.score, v_a.score) then
      v_winner := v_b.user_id; v_reason := 'better_score';
    else
      v_winner := null;       v_reason := 'draw';
    end if;
  elsif v_a_done or v_b_done then
    v_state  := 'decided';
    v_winner := case when v_a_done then v_a.user_id else v_b.user_id end;
    v_reason := case when now() >= v_inst.deadline then 'opponent_timed_out'
                     else 'opponent_did_not_finish' end;
  else
    v_state  := 'expired';
    v_winner := null;
    v_reason := 'neither_finished';
  end if;

  update public.challenge_instances
     set state = v_state,
         winner_user_id = v_winner,
         decided_at = now(),
         decision_reason = v_reason
   where id = p_instance;

  perform rf.emit_event(
    v_inst.rivalry_id, v_winner, 'challenge_decided', 'challenge_instance', p_instance,
    jsonb_build_object(
      'winner_user_id', v_winner,
      'reason', v_reason,
      'scores', jsonb_build_object(v_a.user_id::text, v_a.score, v_b.user_id::text, v_b.score)
    )
  );
end;
$$;

create trigger ca_on_state_change
  after update of state on public.challenge_attempts
  for each row execute function rf.on_attempt_state_change();

-- Deadline sweeper. Invoked by pg_cron (or a scheduled Edge Function) every
-- few minutes; see docs/03-API-ARCHITECTURE.md.
create or replace function rf.sweep_expired_challenges()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id    uuid;
  v_count integer := 0;
begin
  for v_id in
    select i.id from public.challenge_instances i
     where i.state in ('open', 'live') and i.deadline <= now()
     order by i.deadline
     limit 500
  loop
    perform rf.decide_challenge(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke execute on function rf.sweep_expired_challenges() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.challenge_templates      enable row level security;
alter table public.challenge_template_steps enable row level security;
alter table public.challenge_instances      enable row level security;
alter table public.challenge_attempts       enable row level security;
alter table public.challenge_attempt_steps  enable row level security;

-- The catalogue is browsable by every signed-in user, Pro or not.
create policy ct_select_published
  on public.challenge_templates for select to authenticated
  using (published_at is not null);

create policy ct_select_own_draft
  on public.challenge_templates for select to authenticated
  using (created_by = (select auth.uid()));

create policy ct_insert_own
  on public.challenge_templates for insert to authenticated
  with check (created_by = (select auth.uid()) and published_at is null);

create policy ct_update_own_draft
  on public.challenge_templates for update to authenticated
  using      (created_by = (select auth.uid()) and published_at is null)
  with check (created_by = (select auth.uid()));

create policy cts_select_visible
  on public.challenge_template_steps for select to authenticated
  using (exists (
    select 1 from public.challenge_templates t
     where t.id = challenge_template_steps.template_id
       and (t.published_at is not null or t.created_by = (select auth.uid()))
  ));

create policy cts_write_own_draft
  on public.challenge_template_steps for all to authenticated
  using (exists (
    select 1 from public.challenge_templates t
     where t.id = challenge_template_steps.template_id
       and t.created_by = (select auth.uid()) and t.published_at is null
  ))
  with check (exists (
    select 1 from public.challenge_templates t
     where t.id = challenge_template_steps.template_id
       and t.created_by = (select auth.uid()) and t.published_at is null
  ));

create policy ci_select_participant
  on public.challenge_instances for select to authenticated
  using (rf.is_rivalry_member(rivalry_id, (select auth.uid())));

create policy ci_insert_participant
  on public.challenge_instances for insert to authenticated
  with check (
        created_by = (select auth.uid())
    and rf.is_rivalry_member(rivalry_id, (select auth.uid()))
    and state = 'open'
  );

-- Only cancellation is client-driven; every other transition is a trigger's.
create policy ci_update_participant
  on public.challenge_instances for update to authenticated
  using      (rf.is_rivalry_member(rivalry_id, (select auth.uid())))
  with check (rf.is_rivalry_member(rivalry_id, (select auth.uid())));

create policy ca_select_participant
  on public.challenge_attempts for select to authenticated
  using (exists (
    select 1 from public.challenge_instances i
     where i.id = challenge_attempts.instance_id
       and rf.is_rivalry_member(i.rivalry_id, (select auth.uid()))
  ));

create policy ca_update_own
  on public.challenge_attempts for update to authenticated
  using      (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy cas_select_participant
  on public.challenge_attempt_steps for select to authenticated
  using (exists (
    select 1 from public.challenge_attempts a
     join public.challenge_instances i on i.id = a.instance_id
    where a.id = challenge_attempt_steps.attempt_id
      and rf.is_rivalry_member(i.rivalry_id, (select auth.uid()))
  ));

create policy cas_write_own
  on public.challenge_attempt_steps for all to authenticated
  using (exists (
    select 1 from public.challenge_attempts a
     where a.id = challenge_attempt_steps.attempt_id and a.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.challenge_attempts a
     where a.id = challenge_attempt_steps.attempt_id and a.user_id = (select auth.uid())
  ));

grant select                 on public.challenge_templates      to authenticated;
grant insert, update, delete on public.challenge_templates      to authenticated;
grant select, insert, update, delete on public.challenge_template_steps to authenticated;
grant select, insert          on public.challenge_instances     to authenticated;
grant update (state)          on public.challenge_instances     to authenticated;
grant select                  on public.challenge_attempts      to authenticated;
-- score / verified / score_unit are derived; they are not in this list.
grant update (state, started_at, completed_at, elapsed_s, workout_id, proof_url)
  on public.challenge_attempts to authenticated;
grant select, insert, update, delete on public.challenge_attempt_steps to authenticated;
