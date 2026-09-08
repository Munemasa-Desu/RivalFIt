-- 0003 | Profiles
-- One row per auth user. Created by trigger on signup so the client never has
-- to "create my profile" and can never be left half-registered.

create table public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  handle          text not null unique,
  display_name    text,
  avatar_url      text,
  bio             text,
  unit_system     rf.unit_system not null default 'metric',
  timezone        text not null default 'UTC',
  body_weight_kg  numeric(5,2),
  birth_year      integer,
  -- Denormalised so the head-to-head view renders from two rows, not two scans.
  total_workouts  integer not null default 0,
  current_streak  integer not null default 0,
  longest_streak  integer not null default 0,
  last_workout_at timestamptz,
  points_all_time integer not null default 0,
  onboarded_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint profiles_handle_format
    check (handle ~ '^[a-z0-9_]{3,20}$'),
  constraint profiles_bio_len         check (bio is null or length(bio) <= 160),
  constraint profiles_display_len     check (display_name is null or length(display_name) between 1 and 40),
  constraint profiles_birth_year_sane check (birth_year is null or birth_year between 1900 and 2100),
  constraint profiles_weight_sane     check (body_weight_kg is null or body_weight_kg between 20 and 400),
  constraint profiles_streaks_nonneg  check (current_streak >= 0 and longest_streak >= 0)
);

comment on table public.profiles is
  'Public-facing user record. The counters are trigger-maintained; never write them from the client.';

-- Prefix search ("who is @dan...?") without pulling in a trigram index.
-- The format constraint guarantees handles are already lowercase, so a plain
-- text index is case-insensitive in practice.
create index profiles_handle_prefix_idx
  on public.profiles (handle text_pattern_ops);
create index profiles_display_name_prefix_idx
  on public.profiles (lower(display_name) text_pattern_ops)
  where display_name is not null;

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function rf.touch_updated_at();

-- --------------------------------------------------------------------------
-- Signup hook
-- --------------------------------------------------------------------------
-- Runs as the definer inside the auth transaction. A handle collision must not
-- take down signup, so we suffix-retry and fall back to a random handle.

create or replace function rf.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base   text;
  v_handle text;
  v_try    integer := 0;
begin
  v_base := lower(regexp_replace(
    coalesce(
      new.raw_user_meta_data ->> 'handle',
      new.raw_user_meta_data ->> 'preferred_username',
      split_part(coalesce(new.email, ''), '@', 1),
      'athlete'
    ),
    '[^a-zA-Z0-9_]', '', 'g'
  ));

  if length(v_base) < 3 then
    v_base := 'athlete';
  end if;
  v_base := left(v_base, 16);

  v_handle := v_base;
  loop
    begin
      insert into public.profiles (id, handle, display_name, avatar_url)
      values (
        new.id,
        v_handle,
        nullif(new.raw_user_meta_data ->> 'full_name', ''),
        nullif(new.raw_user_meta_data ->> 'avatar_url', '')
      );
      exit;
    exception when unique_violation then
      v_try := v_try + 1;
      if v_try > 5 then
        v_handle := 'a' || replace(gen_random_uuid()::text, '-', '');
        v_handle := left(v_handle, 20);
      else
        v_handle := left(v_base, 16) || v_try::text;
      end if;
    end;
  end loop;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function rf.handle_new_user();

-- --------------------------------------------------------------------------
-- RLS
-- --------------------------------------------------------------------------
-- Deliberately NOT world-readable: a public profiles table is a scrapeable
-- user directory. Strangers are reachable only through rf.search_profiles(),
-- which returns a narrow column set and requires a real query.

alter table public.profiles enable row level security;

create policy profiles_select_self
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));

-- The "rivals can see each other" policy needs rf.shares_rivalry(), which needs
-- the rivalries table. It is added at the end of 0004_social.sql.

create policy profiles_update_self
  on public.profiles for update to authenticated
  using  (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- No insert/delete policy: rows are born in the signup trigger and die with
-- the auth user.

-- Client-writable columns only. Everything else is trigger territory.
revoke update on public.profiles from authenticated;
grant  update (handle, display_name, avatar_url, bio, unit_system,
               timezone, body_weight_kg, birth_year, onboarded_at)
  on public.profiles to authenticated;
grant select on public.profiles to authenticated;
