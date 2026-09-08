-- Signature challenges. Fixed uuids so a re-seed is idempotent and any
-- instance recorded against a template survives a reseed.
--
-- Rule: touch each template exactly once, then publish. After publication the
-- freeze trigger blocks step edits, so a change means bumping `version`.

-- ---------------------------------------------------------------------------
-- HYROX SIMULATION
-- 8 rounds of [1 km Run, station]. Time-scored. Under time cap.
-- ---------------------------------------------------------------------------
insert into public.challenge_templates
  (id, slug, version, name, subtitle, description, category, scoring_type,
   score_unit, time_cap_s, estimated_duration_s, difficulty, equipment, rounds,
   icon, requires_pro)
values (
  '5f000000-0000-0000-0000-000000000001', 'hyrox_sim', 1,
  'Hyrox Simulation',
  '8 rounds. 8 stations. Rack, run, repeat.',
  'The full Hyrox format: 1 km run, then a station, eight times through. '
  'Time-capped at 90 minutes. Winner is the fastest total time.',
  'hyrox', 'time_asc', 'seconds', 5400, 4500, 5,
  array['sled','rower','ski erg','sandbag','wall','medball','kettlebell','burpee broad jump area'],
  8, '🥇', true)
on conflict (slug, version) do nothing;

with t as (select id from public.challenge_templates where slug='hyrox_sim' and version=1),
     e as (select slug, id from public.exercises)
insert into public.challenge_template_steps
  (template_id, block_index, step_index, exercise_id, target_distance_m, target_reps, target_weight_kg, label)
select t.id, b, 0, (select id from e where slug='run_1k'), 1000, null, null, 'Run 1 km'
  from t, generate_series(1,8) as b
where not exists (
  select 1 from public.challenge_template_steps s where s.template_id=t.id and s.block_index=b and s.step_index=0
);

with t as (select id from public.challenge_templates where slug='hyrox_sim' and version=1),
     stations(b, ex, reps, weight, dist, label) as (values
       (1, 'ski_erg',        null, null,  1000, '1 km Ski Erg'),
       (2, 'sled_push',      null, 152.0, 50,   '50 m Sled Push'),
       (3, 'sled_pull',      null, 103.0, 50,   '50 m Sled Pull'),
       (4, 'burpee',         null, null,  80,   '80 m Burpee Broad Jump'),
       (5, 'row_500m',       null, null,  1000, '1 km Row'),
       (6, 'farmers_carry',  null, 24.0,  200,  '200 m Farmer''s Carry'),
       (7, 'sandbag_lunge',  100,  20.0,  null, '100 m Sandbag Lunges'),
       (8, 'wall_ball',      100,  9.0,   null, '100 Wall Balls'))
insert into public.challenge_template_steps
  (template_id, block_index, step_index, exercise_id, target_reps, target_weight_kg, target_distance_m, label)
select t.id, s.b, 1, e.id, s.reps, s.weight, s.dist, s.label
  from t, stations s
  join public.exercises e on e.slug = s.ex
where not exists (
  select 1 from public.challenge_template_steps x where x.template_id=t.id and x.block_index=s.b and x.step_index=1
);

update public.challenge_templates set published_at = coalesce(published_at, now())
 where slug='hyrox_sim' and version=1;

-- ---------------------------------------------------------------------------
-- TACTICAL FITNESS TEST
-- Six-station benchmark. Time-scored on total effort.
-- ---------------------------------------------------------------------------
insert into public.challenge_templates
  (id, slug, version, name, subtitle, description, category, scoring_type,
   score_unit, time_cap_s, estimated_duration_s, difficulty, equipment, rounds,
   icon, requires_pro)
values (
  '5f000000-0000-0000-0000-000000000002', 'tactical_fitness_test', 1,
  'Tactical Fitness Test',
  'Selection-style benchmark. No music. No mercy.',
  'A six-station test modelled on military selection standards. Push-ups, '
  'pull-ups, sit-ups, 5 km run, farmer''s carry, and a shuttle. Winner is '
  'lowest total time to standard.',
  'tactical', 'time_asc', 'seconds', 3600, 2700, 4,
  array['pull-up bar','dumbbell','open track'], 1, '🎖️', false)
on conflict (slug, version) do nothing;

with t as (select id from public.challenge_templates where slug='tactical_fitness_test' and version=1),
     stations(step, ex, reps, dist, weight, label) as (values
       (0, 'push_up',       60, null, null, '60 Push-Ups'),
       (1, 'pull_up',       20, null, null, '20 Pull-Ups'),
       (2, 'sit_up',        60, null, null, '60 Sit-Ups'),
       (3, 'run_5k',        null, 5000, null, '5 km Run'),
       (4, 'farmers_carry', null, 400, 32.0, '400 m Farmer''s Carry @ 32kg'),
       (5, 'burpee',        50, null, null, '50 Burpees'))
insert into public.challenge_template_steps
  (template_id, block_index, step_index, exercise_id, target_reps, target_distance_m, target_weight_kg, label)
select t.id, 0, s.step, e.id, s.reps, s.dist, s.weight, s.label
  from t, stations s join public.exercises e on e.slug=s.ex
where not exists (
  select 1 from public.challenge_template_steps x where x.template_id=t.id and x.step_index=s.step
);

update public.challenge_templates set published_at = coalesce(published_at, now())
 where slug='tactical_fitness_test' and version=1;

-- ---------------------------------------------------------------------------
-- 20-MINUTE AMRAP
-- Community classic. Reps-scored.
-- ---------------------------------------------------------------------------
insert into public.challenge_templates
  (id, slug, version, name, subtitle, description, category, scoring_type,
   score_unit, time_cap_s, estimated_duration_s, difficulty, equipment, rounds,
   icon, requires_pro)
values (
  '5f000000-0000-0000-0000-000000000003', 'amrap_20', 1,
  '"Cindy" — 20 Min AMRAP',
  'Five pull-ups, ten push-ups, fifteen air squats. Twenty minutes.',
  'The benchmark AMRAP. Twenty minutes to bank as many rounds and reps as '
  'you can. Winner has the higher total.',
  'benchmark', 'reps_desc', 'reps', 1200, 1200, 3,
  array['pull-up bar'], 1, '💥', false)
on conflict (slug, version) do nothing;

with t as (select id from public.challenge_templates where slug='amrap_20' and version=1),
     stations(step, ex, reps, label) as (values
       (0, 'pull_up',  5,  '5 Pull-Ups'),
       (1, 'push_up',  10, '10 Push-Ups'),
       (2, 'air_squat',15, '15 Air Squats'))
insert into public.challenge_template_steps
  (template_id, block_index, step_index, exercise_id, target_reps, label)
select t.id, 0, s.step, e.id, s.reps, s.label
  from t, stations s join public.exercises e on e.slug=s.ex
where not exists (
  select 1 from public.challenge_template_steps x where x.template_id=t.id and x.step_index=s.step
);

update public.challenge_templates set published_at = coalesce(published_at, now())
 where slug='amrap_20' and version=1;

-- ---------------------------------------------------------------------------
-- BENCHMARK STRENGTH TOTAL
-- Squat + Bench + Deadlift 1RM. Load-scored on best set weight.
-- ---------------------------------------------------------------------------
insert into public.challenge_templates
  (id, slug, version, name, subtitle, description, category, scoring_type,
   score_unit, time_cap_s, estimated_duration_s, difficulty, equipment, rounds,
   icon, requires_pro)
values (
  '5f000000-0000-0000-0000-000000000004', 'powerlifting_total', 1,
  'Powerlifting Total',
  'Best squat + best bench + best deadlift.',
  'One heavy day. Post your best single for each lift within a week. Highest '
  'total wins.',
  'strength', 'load_desc', 'kg', null, 5400, 4,
  array['barbell','rack','bench'], 1, '🏋️', true)
on conflict (slug, version) do nothing;

with t as (select id from public.challenge_templates where slug='powerlifting_total' and version=1),
     stations(step, ex, label) as (values
       (0, 'back_squat',  'Squat 1RM'),
       (1, 'bench_press', 'Bench 1RM'),
       (2, 'deadlift',    'Deadlift 1RM'))
insert into public.challenge_template_steps
  (template_id, block_index, step_index, exercise_id, target_reps, target_weight_kg, label)
select t.id, 0, s.step, e.id, 1, 100, s.label
  from t, stations s join public.exercises e on e.slug=s.ex
where not exists (
  select 1 from public.challenge_template_steps x where x.template_id=t.id and x.step_index=s.step
);

update public.challenge_templates set published_at = coalesce(published_at, now())
 where slug='powerlifting_total' and version=1;
