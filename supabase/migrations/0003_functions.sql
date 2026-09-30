-- ============================================================
-- QuickServe — 0003_functions.sql
-- Request-ID generation, status transitions, RPC entry points
-- and audit logging. All authorization is re-checked here so
-- the backend never trusts the client.
--
-- NOTE ON DENIALS: authorization failures RETURN a
-- {"denied": true, "message": ...} object instead of RAISEing.
-- A RAISE would roll back the whole PostgREST transaction and
-- take the AUTHORIZATION_FAILED audit row with it. Returning
-- keeps the audit durable while still signalling the client.
-- Validation/state errors still RAISE (nothing to audit there).
-- ============================================================

-- ---------- unique request id: REQ-2026-000123 ----------
-- Always assigned server-side so clients cannot forge ids.
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
security definer
set search_path = public
as $$
begin
  new.request_id := public.generate_request_id();
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
    ('created'::public.request_status,     'assigned'::public.request_status),
    ('created'::public.request_status,     'cancelled'::public.request_status),
    ('assigned'::public.request_status,    'accepted'::public.request_status),
    ('assigned'::public.request_status,    'cancelled'::public.request_status),
    ('accepted'::public.request_status,    'in_progress'::public.request_status),
    ('accepted'::public.request_status,    'cancelled'::public.request_status),
    ('in_progress'::public.request_status, 'completed'::public.request_status),
    ('in_progress'::public.request_status, 'cancelled'::public.request_status)
  );
$$;

-- ---------- append a status history row + audit log ----------
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

-- ---------- durable denial: audits THEN returns an error object ----------
create or replace function public.deny(
  p_action      text,
  p_message     text,
  p_entity_type text default null,
  p_entity_id   text default null
)
returns jsonb
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
    p_entity_type,
    p_entity_id,
    jsonb_build_object('action', p_action)
  );

  return jsonb_build_object('denied', true, 'message', p_message);
end;
$$;

-- ---------- audit log RPC ----------
-- Pre-auth events (LOGIN_FAILED, PASSWORD_RESET_REQUESTED) are allowed
-- for anon so failed sign-ins can still be recorded; everything else
-- requires a session.
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
  v_pre_auth constant text[] := array['LOGIN_FAILED', 'PASSWORD_RESET_REQUESTED'];
begin
  if p_event_type is null or p_event_type <> all (v_allowed) then
    raise exception 'Unknown event type' using errcode = '22023';
  end if;

  if auth.uid() is null and p_event_type <> all (v_pre_auth) then
    raise exception 'Not authenticated' using errcode = '401';
  end if;

  insert into public.audit_logs (actor_id, actor_role, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), public.current_user_role(), p_event_type, p_entity_type, p_entity_id, p_metadata)
  returning id into v_id;

  return v_id;
end;
$$;

-- ============================================================
-- RPC: create_request  (Customer / Admin)  -> jsonb
-- ============================================================
create or replace function public.create_request(
  p_service_id   uuid,
  p_description  text,
  p_preferred_at timestamptz,
  p_address      text,
  p_priority     public.request_priority default 'medium'
)
returns jsonb
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
    return public.deny('create_request',
      'Only customers can create requests', 'service_request');
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

  return to_jsonb(v_row);
end;
$$;

-- ============================================================
-- RPC: assign_agent  (Admin only)  -> jsonb
-- ============================================================
create or replace function public.assign_agent(
  p_request_id uuid,
  p_agent_id   uuid
)
returns jsonb
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
    return public.deny('assign_agent',
      'Only admins can assign agents', 'service_request', p_request_id::text);
  end if;

  select * into v_row from public.service_requests where id = p_request_id for update;
  if not found then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  v_old := v_row.status;

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

  return to_jsonb(v_row);
end;
$$;

-- ============================================================
-- RPC: update_request_status  (role-dependent)  -> jsonb
-- ============================================================
create or replace function public.update_request_status(
  p_request_id uuid,
  p_new_status public.request_status,
  p_note       text default null
)
returns jsonb
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
      return public.deny('update_status',
        'You are not assigned to this request', 'service_request', p_request_id::text);
    end if;
    if p_new_status not in ('accepted', 'in_progress', 'completed') then
      return public.deny('update_status',
        'Agents may only accept, start or complete requests',
        'service_request', p_request_id::text);
    end if;
  elsif v_role = 'customer' then
    if v_row.customer_id is distinct from v_uid then
      return public.deny('update_status',
        'This request does not belong to you', 'service_request', p_request_id::text);
    end if;
    if p_new_status <> 'cancelled' then
      return public.deny('update_status',
        'Customers may only cancel their requests', 'service_request', p_request_id::text);
    end if;
    if v_old not in ('created', 'assigned') then
      raise exception 'This request can no longer be cancelled' using errcode = '22023';
    end if;
  else
    return public.deny('update_status',
      'You are not allowed to manage this request', 'service_request', p_request_id::text);
  end if;

  if v_old = p_new_status then
    return to_jsonb(v_row); -- idempotent no-op
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
  return to_jsonb(v_row);
end;
$$;

-- ============================================================
-- RPC: cancel_request  (Customer own / Admin)  -> jsonb
-- ============================================================
create or replace function public.cancel_request(
  p_request_id uuid,
  p_reason     text default null
)
returns jsonb
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
      return public.deny('cancel_request',
        'This request does not belong to you', 'service_request', p_request_id::text);
    end if;
    if v_old not in ('created', 'assigned') then
      raise exception 'This request can no longer be cancelled' using errcode = '22023';
    end if;
  else
    return public.deny('cancel_request',
      'You are not allowed to cancel this request', 'service_request', p_request_id::text);
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
  return to_jsonb(v_row);
end;
$$;

-- ============================================================
-- RPC: add_note  (customer own / assigned agent / admin)  -> jsonb
-- Appends a note to the status history without changing status.
-- ============================================================
create or replace function public.add_note(
  p_request_id uuid,
  p_note       text
)
returns jsonb
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
  if p_note is null or char_length(trim(p_note)) < 2 then
    raise exception 'Note is too short' using errcode = '22023';
  end if;

  select * into v_row from public.service_requests where id = p_request_id for update;
  if not found then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;

  if v_role = 'admin' then
    null;
  elsif v_role = 'agent' and v_row.agent_id = v_uid then
    null;
  elsif v_role = 'customer' and v_row.customer_id = v_uid then
    null;
  else
    return public.deny('add_note',
      'You are not allowed to comment on this request', 'service_request', p_request_id::text);
  end if;

  insert into public.request_status_history (request_id, from_status, to_status, changed_by, note)
  values (v_row.id, v_row.status, v_row.status, v_uid, trim(p_note));

  insert into public.audit_logs (actor_id, actor_role, event_type, entity_type, entity_id, metadata)
  values (v_uid, v_role, 'REQUEST_UPDATED', 'service_request', v_row.id::text,
          jsonb_build_object('action', 'add_note'));

  return jsonb_build_object('ok', true);
end;
$$;

-- ============================================================
-- RPC: dashboard_stats  (Admin only)  -> jsonb
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
    return public.deny('dashboard_stats', 'Admins only', 'dashboard');
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
-- RPC: admin_set_role  (Admin only)  -> jsonb
-- ============================================================
create or replace function public.admin_set_role(
  p_user_id uuid,
  p_role    public.user_role
)
returns jsonb
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
    return public.deny('set_role', 'Admins only', 'profile', p_user_id::text);
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

  return to_jsonb(v_row);
end;
$$;

-- ============================================================
-- Guard triggers: defense in depth for DIRECT table writes.
-- RLS decides row visibility; these enforce the state machine
-- and block privilege escalation even if a policy were wrong.
-- ============================================================

-- profiles: nobody may change their own role / email / id / active flag
-- unless they are an admin (or a trusted no-JWT context such as a
-- migration, psql session or the service-role key).
create or replace function public.profiles_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new; -- migration / trusted backend context
  end if;

  if new.id is distinct from old.id then
    raise exception 'Profile id cannot be changed' using errcode = '42501';
  end if;

  if new.role is distinct from old.role
     and not public.is_admin() then
    raise exception 'Only admins can change roles' using errcode = '42501';
  end if;

  if new.email is distinct from old.email
     and not public.is_admin() then
    raise exception 'Email cannot be changed here' using errcode = '42501';
  end if;

  if new.is_active is distinct from old.is_active
     and not public.is_admin() then
    raise exception 'Only admins can deactivate accounts' using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger profiles_guard_update
  before update on public.profiles
  for each row execute function public.profiles_guard();

-- service_requests: enforce transitions, actor rights, immutability.
create or replace function public.service_requests_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_role public.user_role;
begin
  if v_uid is null then
    return new; -- migration / trusted backend context
  end if;
  v_role := public.current_user_role();

  if tg_op = 'INSERT' then
    if v_role <> 'admin' and (
         new.customer_id is distinct from v_uid
         or new.status <> 'created'
         or new.agent_id is not null
       ) then
      raise exception 'You cannot create requests for other users' using errcode = '42501';
    end if;
    return new;
  end if;

  -- core fields are immutable for everyone but trusted contexts
  if new.id is distinct from old.id
     or new.request_id is distinct from old.request_id
     or new.customer_id is distinct from old.customer_id
     or new.service_id is distinct from old.service_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Core request fields cannot be modified' using errcode = '42501';
  end if;

  -- only admins may (re)assign agents
  if new.agent_id is distinct from old.agent_id and v_role <> 'admin' then
    raise exception 'Only admins can assign agents' using errcode = '42501';
  end if;

  if new.status is distinct from old.status then
    if old.status in ('completed', 'cancelled') then
      raise exception 'Request is already %', old.status using errcode = '22023';
    end if;
    if not public.is_valid_transition(old.status, new.status) then
      raise exception 'Invalid transition % -> %', old.status, new.status using errcode = '22023';
    end if;

    if v_role = 'admin' then
      null;
    elsif v_role = 'agent' then
      if new.agent_id is distinct from v_uid
         or new.status not in ('accepted', 'in_progress', 'completed') then
        raise exception 'Agents may only progress their assigned requests'
          using errcode = '42501';
      end if;
    else -- customer
      if new.customer_id is distinct from v_uid
         or new.status <> 'cancelled'
         or old.status not in ('created', 'assigned') then
        raise exception 'Customers may only cancel their own open requests'
          using errcode = '42501';
      end if;
    end if;
  end if;

  return new;
end;
$$;

create trigger service_requests_guard_ins
  before insert on public.service_requests
  for each row execute function public.service_requests_guard();

create trigger service_requests_guard_upd
  before update on public.service_requests
  for each row execute function public.service_requests_guard();

-- ============================================================
-- Tighten execute grants.
-- Internal helpers stay callable only by function owners (any RPC
-- runs as SECURITY DEFINER, so it keeps access); clients get the
-- public RPCs plus log_event only.
-- ============================================================
revoke all on function public.record_transition(uuid, public.request_status, public.request_status, text, text) from public, anon, authenticated;
revoke all on function public.deny(text, text, text, text) from public, anon, authenticated;
revoke all on function public.profiles_guard() from public, anon, authenticated;
revoke all on function public.service_requests_guard() from public, anon, authenticated;
revoke all on function public.assign_request_id() from public, anon, authenticated;
revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.prevent_mutation() from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;

revoke all on function public.create_request(uuid, text, timestamptz, text, public.request_priority) from public, anon;
revoke all on function public.assign_agent(uuid, uuid) from public, anon;
revoke all on function public.update_request_status(uuid, public.request_status, text) from public, anon;
revoke all on function public.cancel_request(uuid, text) from public, anon;
revoke all on function public.add_note(uuid, text) from public, anon;
revoke all on function public.dashboard_stats() from public, anon;
revoke all on function public.admin_set_role(uuid, public.user_role) from public, anon;
revoke all on function public.log_event(text, text, text, jsonb) from public;

grant execute on function public.create_request(uuid, text, timestamptz, text, public.request_priority) to authenticated;
grant execute on function public.assign_agent(uuid, uuid) to authenticated;
grant execute on function public.update_request_status(uuid, public.request_status, text) to authenticated;
grant execute on function public.cancel_request(uuid, text) to authenticated;
grant execute on function public.add_note(uuid, text) to authenticated;
grant execute on function public.dashboard_stats() to authenticated;
grant execute on function public.admin_set_role(uuid, public.user_role) to authenticated;
grant execute on function public.log_event(text, text, text, jsonb) to authenticated, anon;
