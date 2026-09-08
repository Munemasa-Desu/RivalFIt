-- 0004 | Blocks, rivalries, and the visibility helpers everything else builds on.
--
-- The rivalry is the product. There is no "competition" object to configure:
-- accepting a request is the entire setup step, and from that moment the pair
-- has a live scoreboard (0008) and can throw challenges at each other (0007).

-- ---------------------------------------------------------------------------
-- Blocks
-- ---------------------------------------------------------------------------

create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_not_self check (blocker_id <> blocked_id)
);

create index blocks_blocked_idx on public.blocks (blocked_id);

-- ---------------------------------------------------------------------------
-- Rivalries
-- ---------------------------------------------------------------------------
-- Stored as an unordered pair: (user_a, user_b) is normalised so user_a is the
-- lexicographically smaller uuid. That turns "is there a rivalry between these
-- two?" into a single unique-index probe instead of a two-branch OR, and makes
-- duplicate-pair prevention a constraint rather than application logic.

create table public.rivalries (
  id           uuid primary key default gen_random_uuid(),
  user_a       uuid not null references public.profiles (id) on delete cascade,
  user_b       uuid not null references public.profiles (id) on delete cascade,
  requested_by uuid not null references public.profiles (id) on delete cascade,
  status       rf.rivalry_status not null default 'pending',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  accepted_at  timestamptz,
  ended_at     timestamptz,
  ended_by     uuid references public.profiles (id) on delete set null,

  constraint rivalries_ordered_pair check (user_a < user_b),
  constraint rivalries_unique_pair  unique (user_a, user_b),
  constraint rivalries_requester_is_member check (requested_by in (user_a, user_b)),
  constraint rivalries_accepted_at_set
    check ((status in ('active', 'paused')) = (accepted_at is not null) or status = 'ended'),
  constraint rivalries_ended_at_set
    check ((status = 'ended') = (ended_at is not null))
);

comment on table public.rivalries is
  'An always-on head-to-head pairing. One row per unordered pair, enforced by the ordered-pair check plus unique index.';

create index rivalries_user_a_idx on public.rivalries (user_a) where status = 'active';
create index rivalries_user_b_idx on public.rivalries (user_b) where status = 'active';
create index rivalries_pending_idx on public.rivalries (user_a, user_b) where status = 'pending';

create trigger rivalries_touch_updated_at
  before update on public.rivalries
  for each row execute function rf.touch_updated_at();

-- Normalise the pair before the constraint (and before RLS WITH CHECK) sees it,
-- so the client can insert (me, them) in whatever order is natural.
create or replace function rf.normalise_rivalry_pair()
returns trigger
language plpgsql
as $$
declare
  v_swap uuid;
begin
  if new.user_a = new.user_b then
    raise exception 'a user cannot be their own rival'
      using errcode = 'check_violation';
  end if;

  if new.user_a > new.user_b then
    v_swap    := new.user_a;
    new.user_a := new.user_b;
    new.user_b := v_swap;
  end if;

  return new;
end;
$$;

create trigger rivalries_normalise_pair
  before insert on public.rivalries
  for each row execute function rf.normalise_rivalry_pair();

-- Blocks beat rivalries, in both directions.
create or replace function rf.reject_blocked_rivalry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.blocks b
    where (b.blocker_id = new.user_a and b.blocked_id = new.user_b)
       or (b.blocker_id = new.user_b and b.blocked_id = new.user_a)
  ) then
    raise exception 'rivalry unavailable between these users'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger rivalries_reject_blocked
  before insert on public.rivalries
  for each row execute function rf.reject_blocked_rivalry();

-- ---------------------------------------------------------------------------
-- Legal status transitions
-- ---------------------------------------------------------------------------
-- RLS can gate *who* may update the row; only a trigger can see OLD and NEW
-- together and gate *how*. Without this, either party could self-accept their
-- own pending request.

create or replace function rf.guard_rivalry_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  -- Service role / background jobs bypass the actor checks but not the graph.
  if v_actor is null then
    v_actor := new.ended_by;
  end if;

  if new.user_a is distinct from old.user_a or new.user_b is distinct from old.user_b then
    raise exception 'rivalry participants are immutable' using errcode = 'check_violation';
  end if;

  if new.status = old.status then
    return new;
  end if;

  case
    -- Only the person who was asked can accept.
    when old.status = 'pending' and new.status = 'active' then
      if v_actor is not null and v_actor = old.requested_by then
        raise exception 'a rivalry request cannot be accepted by its sender'
          using errcode = 'check_violation';
      end if;
      new.accepted_at := coalesce(new.accepted_at, now());

    when old.status = 'pending' and new.status = 'declined' then
      null;

    when old.status = 'active' and new.status = 'paused' then null;
    when old.status = 'paused' and new.status = 'active' then null;

    when old.status in ('pending', 'active', 'paused') and new.status = 'ended' then
      new.ended_at := coalesce(new.ended_at, now());
      new.ended_by := coalesce(new.ended_by, v_actor);

    -- Re-adding someone you previously ended with, without a duplicate row.
    when old.status in ('ended', 'declined') and new.status = 'pending' then
      new.accepted_at := null;
      new.ended_at    := null;
      new.ended_by    := null;
      new.requested_by := coalesce(v_actor, new.requested_by);

    else
      raise exception 'illegal rivalry transition: % -> %', old.status, new.status
        using errcode = 'check_violation';
  end case;

  return new;
end;
$$;

create trigger rivalries_guard_transition
  before update on public.rivalries
  for each row execute function rf.guard_rivalry_transition();

-- Blocking someone ends the rivalry immediately.
create or replace function rf.end_rivalry_on_block()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.rivalries r
     set status   = 'ended',
         ended_at = now(),
         ended_by = new.blocker_id
   where r.status in ('pending', 'active', 'paused')
     and ((r.user_a = new.blocker_id and r.user_b = new.blocked_id)
       or (r.user_a = new.blocked_id and r.user_b = new.blocker_id));
  return new;
end;
$$;

create trigger blocks_end_rivalry
  after insert on public.blocks
  for each row execute function rf.end_rivalry_on_block();

-- ---------------------------------------------------------------------------
-- Visibility helpers
-- ---------------------------------------------------------------------------
-- These are SECURITY DEFINER on purpose. A policy on `rivalries` that queried
-- `rivalries` through a plain SQL function would recurse into its own RLS check
-- and error. Running as the definer reads the table with RLS bypassed, which is
-- safe because each function answers exactly one boolean about the caller and
-- leaks nothing else.

create or replace function rf.shares_rivalry(p_user uuid, p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.rivalries r
     where r.status in ('pending', 'active', 'paused')
       and ((r.user_a = p_user  and r.user_b = p_other)
         or (r.user_a = p_other and r.user_b = p_user))
  );
$$;

create or replace function rf.is_rivalry_member(p_rivalry uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.rivalries r
     where r.id = p_rivalry
       and p_user in (r.user_a, r.user_b)
  );
$$;

-- The other half of a rivalry, or null. Used by the head-to-head view and by
-- every "is this row about my rival?" policy.
create or replace function rf.rival_of(p_rivalry uuid, p_user uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case when r.user_a = p_user then r.user_b else r.user_a end
    from public.rivalries r
   where r.id = p_rivalry
     and p_user in (r.user_a, r.user_b);
$$;

create or replace function rf.is_blocked(p_user uuid, p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.blocks b
     where (b.blocker_id = p_user  and b.blocked_id = p_other)
        or (b.blocker_id = p_other and b.blocked_id = p_user)
  );
$$;

grant execute on function
  rf.shares_rivalry(uuid, uuid),
  rf.is_rivalry_member(uuid, uuid),
  rf.rival_of(uuid, uuid),
  rf.is_blocked(uuid, uuid)
to authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.blocks    enable row level security;
alter table public.rivalries enable row level security;

create policy blocks_owner_all
  on public.blocks for all to authenticated
  using      (blocker_id = (select auth.uid()))
  with check (blocker_id = (select auth.uid()));

-- Note: the blocked user cannot see the row. That is intentional.

create policy rivalries_select_participant
  on public.rivalries for select to authenticated
  using ((select auth.uid()) in (user_a, user_b));

create policy rivalries_insert_self
  on public.rivalries for insert to authenticated
  with check (
        requested_by = (select auth.uid())
    and (select auth.uid()) in (user_a, user_b)
    and status = 'pending'
  );

create policy rivalries_update_participant
  on public.rivalries for update to authenticated
  using      ((select auth.uid()) in (user_a, user_b))
  with check ((select auth.uid()) in (user_a, user_b));

-- No delete policy: rivalries are ended, never erased, so the history that the
-- scoreboard is built on stays intact.

grant select, insert on public.rivalries to authenticated;
grant update (status, ended_by, requested_by) on public.rivalries to authenticated;
grant select, insert, delete on public.blocks to authenticated;

-- Deferred from 0003: rivals may read each other's profile.
create policy profiles_select_rivals
  on public.profiles for select to authenticated
  using (rf.shares_rivalry((select auth.uid()), id));

-- ---------------------------------------------------------------------------
-- Discovery
-- ---------------------------------------------------------------------------
-- profiles is not world-readable, so finding someone to add goes through this
-- narrow RPC: prefix match only, minimum query length, capped result set,
-- fixed column list, blocked users filtered out.

create or replace function public.search_profiles(p_query text)
returns table (
  id           uuid,
  handle       text,
  display_name text,
  avatar_url   text,
  rivalry_status rf.rivalry_status
)
language sql
stable
security definer
set search_path = ''
as $$
  with q as (select lower(trim(coalesce(p_query, ''))) as term)
  select p.id,
         p.handle,
         p.display_name,
         p.avatar_url,
         r.status
    from public.profiles p
    cross join q
    left join public.rivalries r
      on  (r.user_a = least(p.id, auth.uid()) and r.user_b = greatest(p.id, auth.uid()))
   where length(q.term) >= 3
     and p.id <> auth.uid()
     and (p.handle like q.term || '%' or lower(p.display_name) like q.term || '%')
     and not rf.is_blocked(auth.uid(), p.id)
   order by (p.handle = q.term) desc, p.handle
   limit 20;
$$;

revoke execute on function public.search_profiles(text) from public, anon;
grant  execute on function public.search_profiles(text) to authenticated;
