-- Rivalry RLS + transition guards. Run as service role.
\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data) values
 ('11111111-1111-1111-1111-111111111111','dana@x.com','{"handle":"dana"}'),
 ('22222222-2222-2222-2222-222222222222','marco@x.com','{"handle":"marco"}'),
 ('33333333-3333-3333-3333-333333333333','third@x.com','{"handle":"third"}');

-- Dana requests (order deliberately reversed to test the normalise trigger).
begin;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
set local role authenticated;
insert into public.rivalries (user_a, user_b, requested_by)
values ('22222222-2222-2222-2222-222222222222',
        '11111111-1111-1111-1111-111111111111',
        '11111111-1111-1111-1111-111111111111');
-- After the normalise trigger the pair is ordered.
do $$ begin
  if not exists (select 1 from public.rivalries
                  where user_a='11111111-1111-1111-1111-111111111111'
                    and user_b='22222222-2222-2222-2222-222222222222') then
    raise exception 'normalise failed'; end if; end $$;
commit;

-- Sender cannot self-accept — attempt inside a DO block so an EXCEPTION
-- keeps psql's exit code 0. If the update succeeds, the block raises.
begin;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  update public.rivalries set status='active';
  raise exception 'self-accept was allowed but should not be';
exception when others then
  if sqlerrm not like '%cannot be accepted by its sender%' then raise; end if;
end $$;
rollback;

-- Marco accepts.
begin;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
set local role authenticated;
update public.rivalries set status='active';
commit;

-- Third party sees nothing.
begin;
select set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  if (select count(*) from public.rivalries) <> 0 then raise exception 'rls leak on rivalries'; end if;
  if (select count(*) from public.profiles) <> 1  then raise exception 'rls leak on profiles';  end if;
end $$;
commit;

-- Block ends the rivalry.
insert into public.blocks(blocker_id, blocked_id)
values ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');
do $$ begin
  if (select status from public.rivalries limit 1) <> 'ended' then
    raise exception 'block did not end rivalry'; end if; end $$;
