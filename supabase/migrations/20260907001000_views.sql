-- 0010 | Read models the app hits directly
--
-- Every view here is defined `with (security_invoker = true)` so the underlying
-- RLS policies apply to the querying user, not to the view's owner.

-- ---------------------------------------------------------------------------
-- head_to_head: the flagship screen
-- ---------------------------------------------------------------------------
-- Two profile rows joined on one rivalry, with this week's board denormalised
-- into `me_*` and `them_*` columns so the mobile client can render the screen
-- from a single row with no client-side reshaping.
--
-- Realtime subscribes to `public.rivalry_scores` filtered by `rivalry_id`.
-- Both rows for the pair land in that filter, so a change on either athlete
-- refreshes the screen without a second round-trip.

create or replace view public.head_to_head
with (security_invoker = true) as
with me as (
  select (select auth.uid()) as id
),
w as (
  select rf.period_start('week', now())  as week_start,
         rf.period_start('month', now()) as month_start
)
select
    r.id                                                       as rivalry_id,
    r.status,
    r.accepted_at,
    me.id                                                      as me_id,
    case when r.user_a = me.id then r.user_b else r.user_a end as them_id,

    mp.handle       as me_handle,
    mp.display_name as me_display_name,
    mp.avatar_url   as me_avatar_url,
    mp.current_streak as me_streak,
    mp.total_workouts as me_total_workouts,

    tp.handle       as them_handle,
    tp.display_name as them_display_name,
    tp.avatar_url   as them_avatar_url,
    tp.current_streak as them_streak,
    tp.total_workouts as them_total_workouts,

    coalesce(msw.points, 0)     as me_week_points,
    coalesce(msw.workouts, 0)   as me_week_workouts,
    coalesce(msw.volume_kg, 0)  as me_week_volume_kg,
    coalesce(msw.distance_m, 0) as me_week_distance_m,
    coalesce(msw.duration_s, 0) as me_week_duration_s,
    coalesce(msw.challenge_wins, 0) as me_week_challenge_wins,

    coalesce(tsw.points, 0)     as them_week_points,
    coalesce(tsw.workouts, 0)   as them_week_workouts,
    coalesce(tsw.volume_kg, 0)  as them_week_volume_kg,
    coalesce(tsw.distance_m, 0) as them_week_distance_m,
    coalesce(tsw.duration_s, 0) as them_week_duration_s,
    coalesce(tsw.challenge_wins, 0) as them_week_challenge_wins,

    coalesce(msa.points, 0)      as me_all_points,
    coalesce(msa.challenge_wins, 0) as me_all_challenge_wins,
    coalesce(tsa.points, 0)      as them_all_points,
    coalesce(tsa.challenge_wins, 0) as them_all_challenge_wins,

    -- Head-to-head record from closed weeks. Nulls in the count are draws.
    coalesce((
      select count(*) filter (where rr.winner_user_id = me.id)
        from public.rivalry_results rr where rr.rivalry_id = r.id
    ), 0)::integer as me_weeks_won,
    coalesce((
      select count(*) filter (where rr.winner_user_id is distinct from me.id
                                and rr.winner_user_id is not null)
        from public.rivalry_results rr where rr.rivalry_id = r.id
    ), 0)::integer as them_weeks_won,

    w.week_start,
    w.month_start
  from public.rivalries r
  cross join me
  cross join w
  join public.profiles mp on mp.id = me.id
  join public.profiles tp on tp.id = case when r.user_a = me.id then r.user_b else r.user_a end
  left join public.rivalry_scores msw
    on msw.rivalry_id = r.id and msw.user_id = me.id
   and msw.period = 'week' and msw.period_start = w.week_start
  left join public.rivalry_scores tsw
    on tsw.rivalry_id = r.id and tsw.user_id = tp.id
   and tsw.period = 'week' and tsw.period_start = w.week_start
  left join public.rivalry_scores msa
    on msa.rivalry_id = r.id and msa.user_id = me.id
   and msa.period = 'all_time'
  left join public.rivalry_scores tsa
    on tsa.rivalry_id = r.id and tsa.user_id = tp.id
   and tsa.period = 'all_time'
 where r.status in ('active', 'paused')
   and me.id in (r.user_a, r.user_b);

grant select on public.head_to_head to authenticated;

-- ---------------------------------------------------------------------------
-- head_to_head_challenge: the race screen
-- ---------------------------------------------------------------------------

create or replace view public.head_to_head_challenge
with (security_invoker = true) as
with me as (select (select auth.uid()) as id)
select
    i.id                as instance_id,
    i.rivalry_id,
    i.template_id,
    i.template_version,
    i.state,
    i.opens_at,
    i.deadline,
    i.winner_user_id,
    i.decision_reason,
    t.name              as template_name,
    t.category,
    t.scoring_type,
    t.score_unit,
    t.time_cap_s,

    me.id               as me_id,
    ma.state            as me_state,
    ma.started_at       as me_started_at,
    ma.completed_at     as me_completed_at,
    ma.elapsed_s        as me_elapsed_s,
    ma.score            as me_score,
    (select count(*) from public.challenge_attempt_steps s where s.attempt_id = ma.id) as me_steps_done,

    ta.user_id          as them_id,
    ta.state            as them_state,
    ta.started_at       as them_started_at,
    ta.completed_at     as them_completed_at,
    ta.elapsed_s        as them_elapsed_s,
    ta.score            as them_score,
    (select count(*) from public.challenge_attempt_steps s where s.attempt_id = ta.id) as them_steps_done
  from public.challenge_instances i
  join public.challenge_templates t on t.id = i.template_id
  cross join me
  join public.challenge_attempts ma on ma.instance_id = i.id and ma.user_id = me.id
  join public.challenge_attempts ta on ta.instance_id = i.id and ta.user_id <> me.id
 where rf.is_rivalry_member(i.rivalry_id, me.id);

grant select on public.head_to_head_challenge to authenticated;

-- ---------------------------------------------------------------------------
-- rivalry_feed: chronological event stream
-- ---------------------------------------------------------------------------

create or replace view public.rivalry_feed
with (security_invoker = true) as
select
    e.id,
    e.rivalry_id,
    e.kind,
    e.actor_id,
    p.handle       as actor_handle,
    p.display_name as actor_display_name,
    p.avatar_url   as actor_avatar_url,
    e.subject_type,
    e.subject_id,
    e.payload,
    e.created_at
  from public.rivalry_events e
  left join public.profiles p on p.id = e.actor_id;

grant select on public.rivalry_feed to authenticated;
