-- Workout completion → points, streaks, scoreboard, feed.
\set ON_ERROR_STOP on

insert into public.exercises (slug, name, modality, tracks_reps, tracks_weight)
values ('back_squat','Back Squat','strength',true,true) on conflict do nothing;

insert into auth.users (id, email, raw_user_meta_data) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','a@x.com','{"handle":"amy"}'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','b@x.com','{"handle":"ben"}');
update public.profiles set body_weight_kg=70 where handle in ('amy','ben');
insert into public.rivalries (user_a, user_b, requested_by, status, accepted_at)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','active',now());

begin;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);
set local role authenticated;
insert into public.workouts (id, user_id, started_at)
values ('c1111111-1111-1111-1111-111111111111', auth.uid(), now() - interval '35 min');
insert into public.workout_sets (workout_id, exercise_id, set_index, reps, weight_kg)
select 'c1111111-1111-1111-1111-111111111111', e.id, gs, 5, 100
  from public.exercises e, generate_series(1,4) gs where e.slug='back_squat';
update public.workouts set status='completed', ended_at=now(), duration_s=35*60
 where id='c1111111-1111-1111-1111-111111111111';

do $$
declare v_points integer; v_pr numeric; v_scoreboard integer;
begin
  select points into v_points from public.workouts where user_id=auth.uid();
  if v_points <= 0 then raise exception 'scoring produced no points'; end if;

  select value into v_pr from public.personal_records
    where user_id=auth.uid() and metric='max_weight_kg';
  if v_pr <> 100 then raise exception 'PR wrong: %', v_pr; end if;

  select points into v_scoreboard from public.rivalry_scores
    where user_id=auth.uid() and period='week';
  if v_scoreboard <> v_points then raise exception 'scoreboard mismatch: % vs %', v_scoreboard, v_points; end if;
end $$;
commit;

-- Repair produces the same board.
create temp table before_ as select * from public.rivalry_scores;
select rf.recompute_rivalry_scores(id) from public.rivalries limit 1;
do $$
declare v_diff integer;
begin
  select count(*) into v_diff from (
    select * from before_ except select * from public.rivalry_scores
    union all
    select * from public.rivalry_scores except select * from before_
  ) d;
  if v_diff <> 0 then raise exception 'repair diverged from live: % rows', v_diff; end if;
end $$;
