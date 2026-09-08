-- Curated library. Inserted with created_by = null so RLS lets every user read
-- them. Idempotent: rerunning the seed does not duplicate rows.

insert into public.exercises (slug, name, modality, primary_muscle, equipment,
  tracks_reps, tracks_weight, tracks_distance, tracks_duration,
  is_bodyweight, bodyweight_factor, met)
values
  ('back_squat',    'Back Squat',    'strength', 'quads', array['barbell','rack'], true, true,  false, false, false, 1.000, 5.0),
  ('front_squat',   'Front Squat',   'strength', 'quads', array['barbell','rack'], true, true,  false, false, false, 1.000, 5.0),
  ('deadlift',      'Deadlift',      'strength', 'posterior chain', array['barbell'], true, true, false, false, false, 1.000, 6.0),
  ('bench_press',   'Bench Press',   'strength', 'chest', array['barbell','bench'], true, true, false, false, false, 1.000, 4.5),
  ('overhead_press','Overhead Press','strength', 'shoulders', array['barbell'], true, true, false, false, false, 1.000, 4.5),
  ('clean_and_jerk','Clean & Jerk',  'strength', 'full body', array['barbell'], true, true, false, false, false, 1.000, 6.0),
  ('snatch',        'Snatch',        'strength', 'full body', array['barbell'], true, true, false, false, false, 1.000, 6.0),

  ('pull_up',       'Pull-Up',       'bodyweight', 'back',    array['pull-up bar'], true, false, false, false, true,  1.000, 8.0),
  ('push_up',       'Push-Up',       'bodyweight', 'chest',   array[]::text[],      true, false, false, false, true,  0.640, 6.0),
  ('burpee',        'Burpee',        'bodyweight', 'full body', array[]::text[],    true, false, false, false, true,  1.000, 8.0),
  ('air_squat',     'Air Squat',     'bodyweight', 'quads',   array[]::text[],      true, false, false, false, true,  0.500, 5.0),
  ('sit_up',        'Sit-Up',        'bodyweight', 'core',    array[]::text[],      true, false, false, false, true,  0.100, 4.0),

  ('run_1k',        '1 km Run',      'cardio', 'legs', array[]::text[],           false, false, true,  true,  false, 1.000, 9.8),
  ('run_5k',        '5 km Run',      'cardio', 'legs', array[]::text[],           false, false, true,  true,  false, 1.000, 9.8),
  ('row_500m',      '500 m Row',     'cardio', 'full body', array['rower'],       false, false, true,  true,  false, 1.000, 7.0),
  ('assault_bike',  'Assault Bike',  'cardio', 'full body', array['air bike'],    false, false, true,  true,  false, 1.000, 8.0),
  ('ski_erg',       'Ski Erg',       'cardio', 'full body', array['ski erg'],     false, false, true,  true,  false, 1.000, 7.5),

  ('wall_ball',     'Wall Ball',     'strength', 'full body', array['medball','wall'], true, true, false, false, false, 1.000, 6.5),
  ('kettlebell_swing','Kettlebell Swing','strength', 'posterior chain', array['kettlebell'], true, true, false, false, false, 1.000, 8.0),
  ('box_jump',      'Box Jump',      'bodyweight', 'legs', array['box'],           true, false, false, false, true,  1.000, 7.0),

  ('sled_push',     'Sled Push',     'carry', 'legs', array['sled'],              false, true,  true,  false, false, 1.000, 9.0),
  ('sled_pull',     'Sled Pull',     'carry', 'back', array['sled','harness'],    false, true,  true,  false, false, 1.000, 9.0),
  ('farmers_carry', E'Farmer\'s Carry', 'carry', 'full body', array['dumbbell'],    false, true,  true,  false, false, 1.000, 5.5),
  ('sandbag_lunge', 'Sandbag Lunge', 'carry', 'legs', array['sandbag'],           true,  true,  false, false, false, 1.000, 6.5),

  ('plank',         'Plank',         'bodyweight', 'core', array[]::text[],       false, false, false, true,  true,  0.640, 3.0),
  ('mountain_climber','Mountain Climber','bodyweight','full body',array[]::text[],true,  false, false, false, true,  0.400, 8.0)
on conflict (slug) do nothing;
