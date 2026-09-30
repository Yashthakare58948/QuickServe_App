-- ============================================================
-- QuickServe — 0003_functions.sql
-- Request-ID generation, status transitions, RPC entry points
-- and audit logging. All authorization is re-checked here so
-- the backend never trusts the client.
-- ============================================================

-- ---------- unique request id: REQ-2026-000123 ----------
create or replace function public.generate_request_id()
returns text
language sql
as $$
  select 'REQ-' || to_char(now(), 'YYYY') || '-'
       || lpad(nextval('public.request_id_seq')::text, 6, '0');
$$;

create or replace function public.assign_request_id()
returns trigger
language plpgsql
as $$
begin
  if new.request_id is null or new.request_id = '' then
    new.request_id := public.generate_request_id();
  end if;
  return new;
end;
$$;

create trigger service_requests_assign_id
  before insert on public.service_requests
  for each row execute function public.assign_request_id();

-- ---------- allowed transitions ----------
create or replace function public.is_valid_transition(
  from_status public.request_status,
  to_status   public.request_status
)
returns boolean
language sql
immutable
as $$
  select (from_status, to_status) in (
    ('created',     'assigned'),
    ('created',     'cancelled'),
    ('assigned',    'accepted'),
    ('assigned',    'cancelled'),
    ('accepted',    'in_progress'),
    ('accepted',    'cancelled'),
    ('in_progress', 'completed'),
    ('in_progress', 'cancelled')
  );
$$;

-- ---------- append status history + audit log ----------
create or replace function public.record_transition(
  p_request_id uuid,
  p_from       public.request_status,
  p_to         public.request_status,
  p_note       text default null,
  p_event      text default 'REQUEST_UPDATED'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.request_status_history (request_id, from_status, to_status, changed_by, note)
  values (p_request_id, p_from, p_to, auth.uid(), p_note);

  insert into public.audit_logs (actor_id, actor_role, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    public.current_user_role(),
    p_event,
    'service_request',
    p_request_id::text,
    jsonb_build_object('from', p_from, 'to', p_to)
  );
end;
$$;

-- ---------- failed authorization helper ----------
create or replace function public.denied(p_action text, p_entity text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_logs (actor_id, actor_role, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    public.current_user_role(),
    'AUTHORIZATION_FAILED',
    p_entity,
    coalesce(p_entity, p_action),
    jsonb_build_object('action', p_action)
  );
end;
$$;

-- ---------- audit log RPC (client-callable, never logs secrets) ----------
create or replace function public.log_event(
  p_event_type  text,
  p_entity_type text default null,
  p_entity_id   text default null,
  p_metadata    jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_allowed constant text[] := array[
    'LOGIN_SUCCESS', 'LOGIN_FAILED', 'LOGOUT', 'REGISTER_SUCCESS',
    'PASSWORD_RESET_REQUESTED', 'REQUEST_CREATED', 'REQUEST_ASSIGNED',
    'REQUEST_UPDATED', 'REQUEST_CANCELLED', 'PROFILE_UPDATED',
    'AUTHORIZATION_FAILED', 'DATABASE_ERROR'
  ];
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '401';
  end if;
  if p_event_type is null or p_event_type <> all (v_allowed) then
    raise exception 'Unknown event type' using errcode = '22023';
  end if;

  insert into public.audit_logs (actor_id, actor_role, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), public.current_user_role(), p_event_type, p_entity_type, p_entity_id, p_metadata)
  returning id into v_id;

  return v_id;
end;
$$;

-- ============================================================
-- RPC: create_request  (Customer / Admin)
-- ============================================================
create or replace function public.create_request(
  p_service_id   uuid,
  p_description  text,
  p_preferred_at timestamptz,
  p_address      text,
  p_priority     public.request_priority default 'medium'
)
returns public.service_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role := public.current_user_role();
  v_uid  uuid := auth.uid();
  v_row  public.service_requests;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '401';
  end if;
  if v_role is null or v_role not in ('customer', 'admin') then
    perform public.denied('create_request', 'service_request');
    raise exception 'Only customers can create requests' using errcode = '42501';
  end if;

  if p_description is null or char_length(trim(p_description)) < 10 then
    raise exception 'Description must be at least 10 characters' using errcode = '22023';
  end if;
  if p_address is null or char_length(trim(p_address)) < 5 then
    raise exception 'Address must be at least 5 characters' using errcode = '22023';
  end if;
  if p_preferred_at is null or p_preferred_at < now() - interval '1 day' then
    raise exception 'Preferred date/time must be in the future' using errcode = '22023';
  end if;
  if not exists (select 1 from public.services s where s.id = p_service_id and s.is_active) then
    raise exception 'Unknown or inactive service' using errcode = '22023';
  end if;

  insert into public.service_requests
    (customer_id, service_id, description, preferred_at, address, priority, status)
  values
    (v_uid, p_service_id, trim(p_description), p_preferred_at, trim(p_address), p_priority, 'created')
  returning * into v_row;

  insert into public.request_status_history (request_id, from_status, to_status, changed_by, note)
  values (v_row.id, null, 'created', v_uid, 'Request created');

  insert into public.audit_logs (actor_id, actor_role, event_type, entity_type, entity_id, metadata)
  values (v_uid, v_role, 'REQUEST_CREATED', 'service_request', v_row.id::text,
          jsonb_build_object('request_id', v_row.request_id, 'priority', v_row.priority));

  return v_row;
end;
$$;

-- ============================================================
-- RPC: assign_agent  (Admin only)
-- ============================================================
create or replace function public.assign_agent(
  p_request_id uuid,
  p_agent_id   uuid
)
returns public.service_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role := public.current_user_role();
  v_uid  uuid := auth.uid();
  v_old  public.request_status;
  v_row  public.service_requests;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '401';
  end if;
  if v_role is distinct from 'admin' then
    perform public.denied('assign_agent', 'service_request');
    raise exception 'Only admins can assign agents' using errcode = '42501';
  end if;

  select status into v_old
    from public.service_requests
   where id = p_request_id
     for update;
  if not found then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  if v_old not in ('created', 'assigned') then
    raise exception 'Only new or assigned requests can be (re)assigned' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_agent_id and p.role = 'agent') then
    raise exception 'Target user is not an agent' using errcode = '22023';
  end if;

  update public.service_requests
     set agent_id = p_agent_id,
         status   = case when status = 'created' then 'assigned'::public.request_status else status end
   where id = p_request_id
  returning * into v_row;

  if v_old <> v_row.status then
    insert into public.request_status_history (request_id, from_status, to_status, changed_by, note)
    values (v_row.id, v_old, v_row.status, v_uid, 'Agent assigned');
  end if;

  insert into public.audit_logs (actor_id, actor_role, event_type, entity_type, entity_id, metadata)
  values (v_uid, v_role, 'REQUEST_ASSIGNED', 'service_request', v_row.id::text,
          jsonb_build_object('request_id', v_row.request_id, 'agent_id', p_agent_id));

  return v_row;
end;
$$;

-- ============================================================
-- RPC: update_request_status  (role-dependent)
-- ============================================================
create or replace function public.update_request_status(
  p_request_id uuid,
  p_new_status public.request_status,
  p_note       text default null
)
returns public.service_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role := public.current_user_role();
  v_uid  uuid := auth.uid();
  v_old  public.request_status;
  v_row  public.service_requests;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '401';
  end if;

  select * into v_row from public.service_requests where id = p_request_id for update;
  if not found then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  v_old := v_row.status;

  -- who may manage this row at all
  if v_role = 'admin' then
    null;
  elsif v_role = 'agent' then
    if v_row.agent_id is distinct from v_uid then
      perform public.denied('update_status', 'service_request');
      raise exception 'You are not assigned to this request' using errcode = '42501';
    end if;
    if p_new_status not in ('accepted', 'in_progress', 'completed') then
      raise exception 'Agents may only accept, start or complete requests' using errcode = '42501';
    end if;
  elsif v_role = 'customer' then
    if v_row.customer_id is distinct from v_uid then
      perform public.denied('update_status', 'service_request');
      raise exception 'This request does not belong to you' using errcode = '42501';
    end if;
    if p_new_status <> 'cancelled' then
      raise exception 'Customers may only cancel their requests' using errcode = '42501';
    end if;
  else
    perform public.denied('update_status', 'service_request');
    raise exception 'You are not allowed to manage this request' using errcode = '42501';
  end if;

  if v_old = p_new_status then
    return v_row; -- idempotent no-op
  end if;
  if v_old in ('completed', 'cancelled') then
    raise exception 'Request is already %', v_old using errcode = '22023';
  end if;
  if not public.is_valid_transition(v_old, p_new_status) then
    raise exception 'Invalid transition % -> %', v_old, p_new_status using errcode = '22023';
  end if;

  update public.service_requests
     set status = p_new_status
   where id = p_request_id
  returning * into v_row;

  perform public.record_transition(v_row.id, v_old, p_new_status, p_note);
  return v_row;
end;
$$;

-- ============================================================
-- RPC: cancel_request  (Customer own / Admin) — explicit entry
-- ============================================================
create or replace function public.cancel_request(
  p_request_id uuid,
  p_reason     text default null
)
returns public.service_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role := public.current_user_role();
  v_uid  uuid := auth.uid();
  v_old  public.request_status;
  v_row  public.service_requests;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '401';
  end if;

  select * into v_row from public.service_requests where id = p_request_id for update;
  if not found then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  v_old := v_row.status;

  if v_role = 'admin' then
    null;
  elsif v_role = 'customer' then
    if v_row.customer_id is distinct from v_uid then
      perform public.denied('cancel_request', 'service_request');
      raise exception 'This request does not belong to you' using errcode = '42501';
    end if;
    if v_old not in ('created', 'assigned') then
      raise exception 'This request can no longer be cancelled' using errcode = '22023';
    end if;
  else
    perform public.denied('cancel_request', 'service_request');
    raise exception 'You are not allowed to cancel this request' using errcode = '42501';
  end if;

  if v_old in ('completed', 'cancelled') then
    raise exception 'Request is already %', v_old using errcode = '22023';
  end if;

  update public.service_requests
     set status = 'cancelled',
         cancel_reason = coalesce(nullif(trim(p_reason), ''), cancel_reason)
   where id = p_request_id
  returning * into v_row;

  perform public.record_transition(v_row.id, v_old, 'cancelled', p_reason, 'REQUEST_CANCELLED');
  return v_row;
end;
$$;

-- ============================================================
-- RPC: admin dashboard stats  (Admin only)
-- ============================================================
create or replace function public.dashboard_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role   public.user_role := public.current_user_role();
  v_result jsonb;
begin
  if v_role is distinct from 'admin' then
    if auth.uid() is not null then
      perform public.denied('dashboard_stats', 'dashboard');
    end if;
    raise exception 'Admins only' using errcode = '42501';
  end if;

  select jsonb_build_object(
           'total',       count(*),
           'created',     count(*) filter (where status = 'created'),
           'assigned',    count(*) filter (where status = 'assigned'),
           'accepted',    count(*) filter (where status = 'accepted'),
           'in_progress', count(*) filter (where status = 'in_progress'),
           'completed',   count(*) filter (where status = 'completed'),
           'cancelled',   count(*) filter (where status = 'cancelled'),
           'customers',   (select count(*) from public.profiles where role = 'customer'),
           'agents',      (select count(*) from public.profiles where role = 'agent'),
           'open_high',   count(*) filter (
                            where status in ('created','assigned','accepted','in_progress')
                              and priority = 'high')
         )
    into v_result
    from public.service_requests;

  return v_result;
end;
$$;

-- ============================================================
-- RPC: admin_set_role  (Admin only)
-- ============================================================
create or replace function public.admin_set_role(
  p_user_id uuid,
  p_role    public.user_role
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_role public.user_role := public.current_user_role();
  v_row  public.profiles;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '401';
  end if;
  if v_role is distinct from 'admin' then
    perform public.denied('set_role', 'profile');
    raise exception 'Admins only' using errcode = '42501';
  end if;
  if p_user_id = v_uid then
    raise exception 'You cannot change your own role' using errcode = '22023';
  end if;

  update public.profiles set role = p_role where id = p_user_id returning * into v_row;
  if not found then
    raise exception 'User not found' using errcode = 'P0002';
  end if;

  insert into public.audit_logs (actor_id, actor_role, event_type, entity_type, entity_id, metadata)
  values (v_uid, v_role, 'ROLE_CHANGED', 'profile', p_user_id::text, jsonb_build_object('role', p_role));

  return v_row;
end;
$$;

-- ---------- tighten execute grants ----------
revoke all on function public.create_request(uuid, text, timestamptz, text, public.request_priority) from public, anon;
revoke all on function public.assign_agent(uuid, uuid) from public, anon;
revoke all on function public.update_request_status(uuid, public.request_status, text) from public, anon;
revoke all on function public.cancel_request(uuid, text) from public, anon;
revoke all on function public.dashboard_stats() from public, anon;
revoke all on function public.admin_set_role(uuid, public.user_role) from public, anon;
revoke all on function public.log_event(text, text, text, jsonb) from public, anon;
revoke all on function public.record_transition(uuid, public.request_status, public.request_status, text, text) from public, anon;
revoke all on function public.denied(text, text) from public, anon;

grant execute on function public.create_request(uuid, text, timestamptz, text, public.request_priority) to authenticated;
grant execute on function public.assign_agent(uuid, uuid) to authenticated;
grant execute on function public.update_request_status(uuid, public.request_status, text) to authenticated;
grant execute on function public.cancel_request(uuid, text) to authenticated;
grant execute on function public.dashboard_stats() to authenticated;
grant execute on function public.admin_set_role(uuid, public.user_role) to authenticated;
grant execute on function public.log_event(text, text, text, jsonb) to authenticated;
