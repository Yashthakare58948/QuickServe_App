-- ============================================================
-- QuickServe — 0002_rls_policies.sql
-- Row Level Security: authorization enforced in the database.
-- ============================================================

-- ---------- Security helpers (SECURITY DEFINER avoids policy recursion) ----------
create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select p.role from public.profiles p where p.id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_user_role() = 'admin', false);
$$;

create or replace function public.is_authenticated()
returns boolean
language sql
stable
as $$
  select auth.uid() is not null;
$$;

revoke execute on function public.current_user_role() from public, anon;
revoke execute on function public.is_admin() from public, anon;
grant  execute on function public.current_user_role() to authenticated;
grant  execute on function public.is_admin() to authenticated;

-- ============================================================
-- profiles
-- ============================================================
alter table public.profiles enable row level security;

create policy "profiles_select_self"
  on public.profiles for select
  to authenticated
  using (id = auth.uid());

create policy "profiles_select_admin"
  on public.profiles for select
  to authenticated
  using (public.is_admin());

-- agent can see customers whose requests are assigned to them
create policy "profiles_select_agent_of_customer"
  on public.profiles for select
  to authenticated
  using (
    role = 'customer'
    and exists (
      select 1 from public.service_requests sr
      where sr.customer_id = public.profiles.id
        and sr.agent_id = auth.uid()
    )
  );

-- customer can see the agent assigned to one of their requests
create policy "profiles_select_customer_of_agent"
  on public.profiles for select
  to authenticated
  using (
    role = 'agent'
    and exists (
      select 1 from public.service_requests sr
      where sr.agent_id = public.profiles.id
        and sr.customer_id = auth.uid()
    )
  );

create policy "profiles_update_self"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy "profiles_update_admin"
  on public.profiles for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ============================================================
-- services
-- ============================================================
alter table public.services enable row level security;

create policy "services_select_authenticated"
  on public.services for select
  to authenticated
  using (true);

create policy "services_write_admin"
  on public.services for insert
  to authenticated
  with check (public.is_admin());

create policy "services_update_admin"
  on public.services for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy "services_delete_admin"
  on public.services for delete
  to authenticated
  using (public.is_admin());

-- ============================================================
-- service_requests
-- ============================================================
alter table public.service_requests enable row level security;

create policy "requests_select_own"
  on public.service_requests for select
  to authenticated
  using (customer_id = auth.uid());

create policy "requests_select_assigned"
  on public.service_requests for select
  to authenticated
  using (agent_id = auth.uid());

create policy "requests_select_admin"
  on public.service_requests for select
  to authenticated
  using (public.is_admin());

create policy "requests_insert_self"
  on public.service_requests for insert
  to authenticated
  with check (
    customer_id = auth.uid()
    and status = 'created'
    and agent_id is null
  );

create policy "requests_insert_admin"
  on public.service_requests for insert
  to authenticated
  with check (public.is_admin());

create policy "requests_update_own"
  on public.service_requests for update
  to authenticated
  using (customer_id = auth.uid())
  with check (customer_id = auth.uid());

create policy "requests_update_assigned"
  on public.service_requests for update
  to authenticated
  using (agent_id = auth.uid())
  with check (agent_id = auth.uid());

create policy "requests_update_admin"
  on public.service_requests for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ============================================================
-- request_status_history
-- ============================================================
alter table public.request_status_history enable row level security;

create policy "history_select_participants"
  on public.request_status_history for select
  to authenticated
  using (
    public.is_admin()
    or exists (
      select 1 from public.service_requests sr
      where sr.id = request_status_history.request_id
        and (sr.customer_id = auth.uid() or sr.agent_id = auth.uid())
    )
  );

-- inserts only via SECURITY DEFINER functions/triggers (no client policy)

-- ============================================================
-- audit_logs
-- ============================================================
alter table public.audit_logs enable row level security;

create policy "audit_select_admin"
  on public.audit_logs for select
  to authenticated
  using (public.is_admin());

-- inserts only via the log_event() RPC / SECURITY DEFINER functions

-- ============================================================
-- Revoke everything from anon (backend requires a session)
-- ============================================================
revoke all on public.profiles            from anon;
revoke all on public.services            from anon;
revoke all on public.service_requests    from anon;
revoke all on public.request_status_history from anon;
revoke all on public.audit_logs          from anon;
