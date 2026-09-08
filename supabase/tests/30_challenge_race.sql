-- One rivalry, one Hyrox instance, both finish, Ben wins on time_asc.
\set ON_ERROR_STOP on

-- Amy pays for Pro; Hyrox is Pro-gated by the seed.
update public.subscriptions set tier='pro', current_period_end=now() + interval '30 days',
       stripe_subscription_id='sub_test_amy'
 where user_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

insert into public.challenge_instances (id, rivalry_id, template_id, created_by, deadline)
select 'e0000000-0000-0000-0000-000000000001', r.id,
       (select id from public.challenge_templates where slug='hyrox_sim' and version=1),
       'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       now() + interval '7 days'
  from public.rivalries r where r.user_a='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and r.user_b='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

do $$ begin
  if (select count(*) from public.challenge_attempts where instance_id='e0000000-0000-0000-0000-000000000001') <> 2 then
    raise exception 'attempts not seeded';
  end if;
end $$;

-- Amy 45:00, Ben 40:00
update public.challenge_attempts set state='in_progress', started_at = now() - interval '45 min'
 where instance_id='e0000000-0000-0000-0000-000000000001' and user_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
update public.challenge_attempts set state='completed', completed_at=now()
 where instance_id='e0000000-0000-0000-0000-000000000001' and user_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

update public.challenge_attempts set state='in_progress', started_at = now() - interval '40 min'
 where instance_id='e0000000-0000-0000-0000-000000000001' and user_id='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
update public.challenge_attempts set state='completed', completed_at=now()
 where instance_id='e0000000-0000-0000-0000-000000000001' and user_id='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

do $$
declare v_winner uuid; v_state rf.challenge_state;
begin
  select state, winner_user_id into v_state, v_winner
    from public.challenge_instances where id='e0000000-0000-0000-0000-000000000001';
  if v_state <> 'decided' then raise exception 'race not decided: %', v_state; end if;
  if v_winner <> 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' then
    raise exception 'wrong winner: %', v_winner; end if;
end $$;
