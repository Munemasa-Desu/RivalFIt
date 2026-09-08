-- 0004b | Rivalry activity stream
--
-- The feed the head-to-head screen subscribes to over Realtime. Deliberately
-- FK-free on `subject_id`: this table is append-only history, and a deleted
-- workout should not vacuum a lead change out of the record.

create table public.rivalry_events (
  id           bigint generated always as identity primary key,
  rivalry_id   uuid not null references public.rivalries (id) on delete cascade,
  actor_id     uuid references public.profiles (id) on delete set null,
  kind         rf.event_kind not null,
  subject_type text,
  subject_id   uuid,
  payload      jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);

create index rivalry_events_feed_idx on public.rivalry_events (rivalry_id, created_at desc);
create index rivalry_events_actor_idx on public.rivalry_events (actor_id, created_at desc);

create or replace function rf.emit_event(
  p_rivalry      uuid,
  p_actor        uuid,
  p_kind         rf.event_kind,
  p_subject_type text default null,
  p_subject_id   uuid default null,
  p_payload      jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
begin
  insert into public.rivalry_events (rivalry_id, actor_id, kind, subject_type, subject_id, payload)
  values (p_rivalry, p_actor, p_kind, p_subject_type, p_subject_id, p_payload)
  returning id into v_id;
  return v_id;
end;
$$;

revoke execute on function rf.emit_event(uuid, uuid, rf.event_kind, text, uuid, jsonb)
  from public, anon, authenticated;

alter table public.rivalry_events enable row level security;

create policy rivalry_events_select_participant
  on public.rivalry_events for select to authenticated
  using (rf.is_rivalry_member(rivalry_id, (select auth.uid())));

-- Insert-only via triggers and taunts; no client writes at all.
grant select on public.rivalry_events to authenticated;

-- ---------------------------------------------------------------------------
-- Taunts
-- ---------------------------------------------------------------------------
-- The one thing a user writes directly to a rival. Rate limited in the
-- database, because a limit that lives only in the client is not a limit.

create table public.taunts (
  id         uuid primary key default gen_random_uuid(),
  rivalry_id uuid not null references public.rivalries (id) on delete cascade,
  from_id    uuid not null references public.profiles (id) on delete cascade,
  to_id      uuid not null references public.profiles (id) on delete cascade,
  preset     text,
  body       text,
  created_at timestamptz not null default now(),

  constraint taunts_not_self check (from_id <> to_id),
  constraint taunts_has_content check (num_nonnulls(preset, body) > 0),
  constraint taunts_body_len check (body is null or length(body) <= 140)
);

create index taunts_rivalry_idx on public.taunts (rivalry_id, created_at desc);
create index taunts_rate_idx    on public.taunts (from_id, created_at desc);

create or replace function rf.guard_taunt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recent integer;
  v_other  uuid;
begin
  if not rf.is_rivalry_member(new.rivalry_id, new.from_id) then
    raise exception 'not a member of this rivalry' using errcode = 'insufficient_privilege';
  end if;

  v_other := rf.rival_of(new.rivalry_id, new.from_id);
  if new.to_id is distinct from v_other then
    raise exception 'a taunt must be addressed to your rival' using errcode = 'check_violation';
  end if;

  select count(*) into v_recent
    from public.taunts t
   where t.from_id = new.from_id
     and t.created_at > now() - interval '1 hour';

  if v_recent >= 10 then
    raise exception 'taunt rate limit reached, cool off' using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger taunts_guard
  before insert on public.taunts
  for each row execute function rf.guard_taunt();

create or replace function rf.emit_taunt_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform rf.emit_event(
    new.rivalry_id, new.from_id, 'taunt', 'taunt', new.id,
    jsonb_build_object('preset', new.preset, 'body', new.body)
  );
  return null;
end;
$$;

create trigger taunts_emit_event
  after insert on public.taunts
  for each row execute function rf.emit_taunt_event();

alter table public.taunts enable row level security;

create policy taunts_select_participant
  on public.taunts for select to authenticated
  using (rf.is_rivalry_member(rivalry_id, (select auth.uid())));

create policy taunts_insert_self
  on public.taunts for insert to authenticated
  with check (from_id = (select auth.uid()));

grant select, insert on public.taunts to authenticated;
