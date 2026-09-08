-- 0007 | Stripe billing
--
-- The client never writes here. Stripe webhooks land in an Edge Function that
-- uses the service role; the app only reads its own entitlement row.

create table public.subscriptions (
  user_id                uuid primary key references public.profiles (id) on delete cascade,
  tier                   rf.plan_tier not null default 'free',
  stripe_customer_id     text unique,
  stripe_subscription_id text unique,
  price_id               text,
  status                 text,
  current_period_end     timestamptz,
  cancel_at_period_end   boolean not null default false,
  trial_end              timestamptz,
  updated_at             timestamptz not null default now(),

  constraint subscriptions_pro_needs_stripe
    check (tier = 'free' or stripe_subscription_id is not null)
);

comment on table public.subscriptions is
  'Mirror of Stripe state, written only by the stripe-webhook Edge Function. Stripe is the source of truth; this table is the read cache the app gates on.';

create trigger subscriptions_touch_updated_at
  before update on public.subscriptions
  for each row execute function rf.touch_updated_at();

-- Webhook idempotency. Stripe retries; `event_id` as the primary key means a
-- replayed delivery is a no-op instead of a double-grant.
create table public.stripe_events (
  event_id     text primary key,
  type         text not null,
  payload      jsonb not null,
  received_at  timestamptz not null default now(),
  processed_at timestamptz,
  error        text
);

alter table public.stripe_events enable row level security;
-- No policies: service role only.

-- Entitlement check used by challenge gating. Treats an expired period as free
-- even if a webhook was missed, so a lapsed card cannot keep Pro open forever.
create or replace function rf.has_pro(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.subscriptions s
     where s.user_id = p_user
       and s.tier = 'pro'
       and (s.current_period_end is null or s.current_period_end > now())
  );
$$;

grant execute on function rf.has_pro(uuid) to authenticated;

create or replace function rf.ensure_subscription_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.subscriptions (user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger profiles_ensure_subscription
  after insert on public.profiles
  for each row execute function rf.ensure_subscription_row();

alter table public.subscriptions enable row level security;

create policy subscriptions_select_self
  on public.subscriptions for select to authenticated
  using (user_id = (select auth.uid()));

-- No insert/update/delete policy for `authenticated`: entitlements are not
-- client-writable under any circumstances.
grant select on public.subscriptions to authenticated;

-- Backfill for profiles created before this migration.
insert into public.subscriptions (user_id)
select p.id from public.profiles p
on conflict (user_id) do nothing;
