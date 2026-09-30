-- ============================================================
-- QuickServe — 0001_schema.sql
-- Tables, enums, indexes, triggers.
-- Apply in the Supabase SQL editor (in numerical order).
-- ============================================================

-- ---------- Enums ----------
create type public.user_role as enum ('customer', 'agent', 'admin');
create type public.request_priority as enum ('low', 'medium', 'high');
create type public.request_status as enum (
  'created',
  'assigned',
  'accepted',
  'in_progress',
  'completed',
  'cancelled'
);

-- ---------- profiles (1:1 with auth.users) ----------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text not null,
  full_name   text not null default '',
  phone       text,
  role        public.user_role not null default 'customer',
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index profiles_role_idx on public.profiles (role);

-- ---------- services ----------
create table public.services (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  description text not null default '',
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

-- ---------- service_requests ----------
create table public.service_requests (
  id           uuid primary key default gen_random_uuid(),
  request_id   text not null unique,
  customer_id  uuid not null references public.profiles (id) on delete restrict,
  agent_id     uuid references public.profiles (id) on delete set null,
  service_id   uuid not null references public.services (id) on delete restrict,
  description  text not null,
  preferred_at timestamptz not null,
  address      text not null,
  priority     public.request_priority not null default 'medium',
  status       public.request_status not null default 'created',
  cancel_reason text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint service_requests_description_len
    check (char_length(description) between 10 and 2000),
  constraint service_requests_address_len
    check (char_length(address) between 5 and 500)
);

create index service_requests_customer_idx on public.service_requests (customer_id, created_at desc);
create index service_requests_agent_idx    on public.service_requests (agent_id, status);
create index service_requests_status_idx   on public.service_requests (status, created_at desc);
create index service_requests_service_idx  on public.service_requests (service_id);

-- request_id sequence, e.g. REQ-2026-000123
create sequence public.request_id_seq start 1;

-- ---------- request_status_history (append-only) ----------
create table public.request_status_history (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.service_requests (id) on delete cascade,
  from_status public.request_status,
  to_status   public.request_status not null,
  changed_by  uuid references public.profiles (id) on delete set null,
  note        text,
  created_at  timestamptz not null default now()
);

create index request_status_history_request_idx
  on public.request_status_history (request_id, created_at);

-- ---------- audit_logs (append-only, no secrets ever) ----------
create table public.audit_logs (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid references public.profiles (id) on delete set null,
  actor_role  public.user_role,
  event_type  text not null,
  entity_type text,
  entity_id   text,
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create index audit_logs_created_idx on public.audit_logs (created_at desc);
create index audit_logs_actor_idx   on public.audit_logs (actor_id, created_at desc);
create index audit_logs_entity_idx  on public.audit_logs (entity_id);
create index audit_logs_event_idx   on public.audit_logs (event_type, created_at desc);

-- ---------- append-only guards ----------
create or replace function public.prevent_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Table % is append-only', tg_table_name
    using errcode = '42501';
end;
$$;

create trigger request_status_history_no_update
  before update or delete on public.request_status_history
  for each row execute function public.prevent_mutation();

create trigger audit_logs_no_update
  before update or delete on public.audit_logs
  for each row execute function public.prevent_mutation();

-- ---------- updated_at trigger ----------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger service_requests_updated_at
  before update on public.service_requests
  for each row execute function public.set_updated_at();

-- ---------- auto-create profile on signup ----------
-- role is only ever 'customer' at signup; admins promote via admin_set_role()
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
