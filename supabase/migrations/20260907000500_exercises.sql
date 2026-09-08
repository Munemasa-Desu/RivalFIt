-- 0005 | Exercise library
--
-- Canonical movements. Challenge templates reference these rather than storing
-- free text, so "100 wall balls" in the Hyrox sim and "100 wall balls" a user
-- logs by hand roll up to the same PR and the same comparison row in the
-- head-to-head view.

create table public.exercises (
  id              uuid primary key default gen_random_uuid(),
  slug            text not null unique,
  name            text not null,
  modality        rf.exercise_modality not null,
  primary_muscle  text,
  equipment       text[] not null default '{}',

  -- Which metrics are meaningful for this movement. The logger renders inputs
  -- from these flags, and the aggregate trigger only sums what is tracked.
  tracks_reps     boolean not null default true,
  tracks_weight   boolean not null default false,
  tracks_distance boolean not null default false,
  tracks_duration boolean not null default false,

  -- Bodyweight movements score volume against profiles.body_weight_kg.
  is_bodyweight   boolean not null default false,
  bodyweight_factor numeric(4,3) not null default 1.000,

  met             numeric(4,2),
  created_by      uuid references public.profiles (id) on delete cascade,
  created_at      timestamptz not null default now(),

  constraint exercises_slug_format check (slug ~ '^[a-z0-9_]{2,60}$'),
  constraint exercises_tracks_something
    check (tracks_reps or tracks_weight or tracks_distance or tracks_duration),
  constraint exercises_bw_factor_sane check (bodyweight_factor between 0 and 2)
);

comment on column public.exercises.created_by is
  'NULL means an official library movement. Non-null is a user-authored custom movement.';

create index exercises_modality_idx on public.exercises (modality);
create index exercises_official_idx on public.exercises (slug) where created_by is null;

alter table public.exercises enable row level security;

create policy exercises_select_official
  on public.exercises for select to authenticated
  using (created_by is null);

create policy exercises_select_own
  on public.exercises for select to authenticated
  using (created_by = (select auth.uid()));

create policy exercises_insert_own
  on public.exercises for insert to authenticated
  with check (created_by = (select auth.uid()));

create policy exercises_update_own
  on public.exercises for update to authenticated
  using      (created_by = (select auth.uid()))
  with check (created_by = (select auth.uid()));

create policy exercises_delete_own
  on public.exercises for delete to authenticated
  using (created_by = (select auth.uid()));

grant select, insert, update, delete on public.exercises to authenticated;
