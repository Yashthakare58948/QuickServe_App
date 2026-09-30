-- ============================================================
-- QuickServe — tests/authorization_test.sql
-- Backend authorization test (run in the Supabase SQL editor).
--
-- Verifies, at the database layer:
--   1. Customer B cannot SELECT customer A's request
--   2. Customer B cannot SELECT A's status history
--   3. Customer B cannot UPDATE customer A's request
--   4. cancel_request() by B returns a denial object AND audits it
--   5. dashboard_stats() returns a denial object for non-admins
--   6. A customer cannot INSERT a request on someone else's behalf
--   7. An agent cannot SELECT an unassigned request
--   8. The owner can still SELECT her own request
--   9. A customer cannot promote themselves to admin
--  10. admin_set_role() by a customer returns a denial object AND audits it
--  11. admin_create_agent() by a customer returns a denial object AND audits it
--  12. admin_create_agent() by an admin creates a usable agent account
--      (profile role = agent, password verifies, no password in the audit log)
--  13. deleting an account keeps every audit row (FK ON DELETE SET NULL
--      still works against the append-only table; direct UPDATEs do not)
--
-- Authorization denials RETURN {"denied": true, "message": ...}
-- (see 0003_functions.sql — a RAISE would roll back the audit row),
-- while direct table writes still RAISE 42501.
--
-- Everything runs inside a transaction that is rolled back, so the
-- project data is left untouched.
-- ============================================================

begin;

-- ---------- test fixtures (as table owner / superuser) ----------
-- profiles.id references auth.users, and a trigger creates the profile
-- on signup — so the fixtures go through auth.users like real signups.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111',
   'authenticated', 'authenticated', 'authz-a@test.dev', crypt('AuthZTest1!', gen_salt('bf')),
   now(), '{"provider":"email","providers":["email"]}', '{"full_name":"AuthZ Customer A"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222',
   'authenticated', 'authenticated', 'authz-b@test.dev', crypt('AuthZTest1!', gen_salt('bf')),
   now(), '{"provider":"email","providers":["email"]}', '{"full_name":"AuthZ Customer B"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '33333333-3333-3333-3333-333333333333',
   'authenticated', 'authenticated', 'authz-agent@test.dev', crypt('AuthZTest1!', gen_salt('bf')),
   now(), '{"provider":"email","providers":["email"]}', '{"full_name":"AuthZ Agent"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '44444444-4444-4444-4444-444444444444',
   'authenticated', 'authenticated', 'authz-admin@test.dev', crypt('AuthZTest1!', gen_salt('bf')),
   now(), '{"provider":"email","providers":["email"]}', '{"full_name":"AuthZ Admin"}', now(), now())
on conflict (id) do nothing;

-- promote the third fixture user to agent (owner context: guard allows it)
update public.profiles
   set role = 'agent', full_name = 'AuthZ Agent'
 where id = '33333333-3333-3333-3333-333333333333';

-- and the fourth to admin (needed by test 12)
update public.profiles
   set role = 'admin', full_name = 'AuthZ Admin'
 where id = '44444444-4444-4444-4444-444444444444';

-- a request owned by customer A (owner insert bypasses RLS by design)
insert into public.service_requests
  (id, request_id, customer_id, service_id, description, preferred_at, address, priority, status)
select
  'aaaaaaaa-0000-0000-0000-000000000001',
  'REQ-2026-999901',
  '11111111-1111-1111-1111-111111111111',
  s.id,
  'Authorization test request owned by A',
  now() + interval '2 days',
  '12 Test Street, Nagpur',
  'high',
  'created'
from public.services s
where s.name = 'AC Servicing'
limit 1
on conflict (request_id) do nothing;

-- ---------- TEST 1: B cannot see A's request ----------
set role authenticated;
set "request.jwt.claims" to '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
    from public.service_requests
   where id = 'aaaaaaaa-0000-0000-0000-000000000001';

  if v_count <> 0 then
    raise exception 'FAIL test1: customer B can see customer A''s request (rows=%)', v_count;
  end if;
  raise notice 'PASS test1: customer B cannot SELECT customer A''s request';
end;
$$;

-- B also must not see A's request through the history table
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
    from public.request_status_history
   where request_id = 'aaaaaaaa-0000-0000-0000-000000000001';

  if v_count <> 0 then
    raise exception 'FAIL test2: customer B can see A''s status history';
  end if;
  raise notice 'PASS test2: customer B cannot SELECT A''s status history';
end;
$$;

-- ---------- TEST 3: B cannot UPDATE A's request ----------
do $$
begin
  update public.service_requests
     set status = 'cancelled'
   where id = 'aaaaaaaa-0000-0000-0000-000000000001';

  if found then
    raise exception 'FAIL test3: customer B updated customer A''s request';
  end if;
  raise notice 'PASS test3: customer B UPDATE on A''s request affected 0 rows';
end;
$$;

-- ---------- TEST 4: cancel_request() denies B with a denial object ----------
do $$
declare
  v_result jsonb;
begin
  v_result := public.cancel_request(
    'aaaaaaaa-0000-0000-0000-000000000001',
    'not mine'
  );

  if v_result is null
     or coalesce((v_result ->> 'denied')::boolean, false) is not true then
    raise exception 'FAIL test4: cancel_request() was NOT denied for customer B (got %)', v_result;
  end if;

  raise notice 'PASS test4: cancel_request denied for customer B';
end;
$$;

-- ---------- TEST 5: dashboard_stats() denied (denial object) for non-admin ----------
do $$
declare
  v_result jsonb;
begin
  v_result := public.dashboard_stats();

  if v_result is null
     or coalesce((v_result ->> 'denied')::boolean, false) is not true then
    raise exception 'FAIL test5: dashboard_stats() allowed for a customer (got %)', v_result;
  end if;

  raise notice 'PASS test5: dashboard_stats() denied for customer';
end;
$$;

-- ---------- TEST 6: B cannot insert a request as A ----------
do $$
declare
  v_denied boolean := false;
begin
  begin
    insert into public.service_requests
      (customer_id, service_id, description, preferred_at, address, priority, status)
    select
      '11111111-1111-1111-1111-111111111111',
      s.id,
      'forged request by B',
      now() + interval '1 day',
      '9 Forged Lane, Nagpur',
      'low',
      'created'
    from public.services s limit 1;
  exception
    when others then
      if sqlstate in ('42501', '23514') then
        v_denied := true;
      else
        raise;
      end if;
  end;

  if not v_denied then
    raise exception 'FAIL test6: B inserted a request owned by A';
  end if;
  raise notice 'PASS test6: inserting a request as another customer is denied';
end;
$$;

-- ---------- TEST 7: agent cannot see unassigned request ----------
set "request.jwt.claims" to '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
    from public.service_requests
   where id = 'aaaaaaaa-0000-0000-0000-000000000001';

  if v_count <> 0 then
    raise exception 'FAIL test7: agent sees an unassigned request';
  end if;
  raise notice 'PASS test7: agent cannot SELECT an unassigned request';
end;
$$;

-- ---------- TEST 8: customer A still sees her own request (untouched) ----------
set "request.jwt.claims" to '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

do $$
declare
  v_count  integer;
  v_status public.request_status;
begin
  select count(*) into v_count
    from public.service_requests
   where id = 'aaaaaaaa-0000-0000-0000-000000000001';

  if v_count <> 1 then
    raise exception 'FAIL test8: owner cannot see her own request (rows=%)', v_count;
  end if;

  -- the denied cancel_request in test 4 must not have mutated anything
  select status into v_status
    from public.service_requests
   where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  if v_status <> 'created' then
    raise exception 'FAIL test8: request mutated by denied call (status=%)', v_status;
  end if;

  raise notice 'PASS test8: customer A can SELECT her own request and it is untouched';
end;
$$;

-- ---------- TEST 9: a customer cannot promote themselves to admin ----------
do $$
begin
  begin
    update public.profiles
       set role = 'admin'
     where id = '11111111-1111-1111-1111-111111111111';
    raise exception 'FAIL test9: customer self-promoted to admin';
  exception
    when others then
      if sqlstate <> '42501' then
        raise;
      end if;
  end;
  raise notice 'PASS test9: self-promotion to admin is blocked (42501)';
end;
$$;

-- ---------- TEST 10: admin_set_role() by a customer is denied ----------
do $$
declare
  v_result jsonb;
begin
  v_result := public.admin_set_role('33333333-3333-3333-3333-333333333333', 'admin');

  if v_result is null
     or coalesce((v_result ->> 'denied')::boolean, false) is not true then
    raise exception 'FAIL test10: admin_set_role() was NOT denied for a customer (got %)', v_result;
  end if;

  raise notice 'PASS test10: admin_set_role denied for customer';
end;
$$;

-- ---------- TEST 11: admin_create_agent() by a customer is denied ----------
do $$
declare
  v_result jsonb;
begin
  v_result := public.admin_create_agent(
    'authz-new-agent@test.dev', 'AgentTest1!', 'AuthZ New Agent');

  if v_result is null
     or coalesce((v_result ->> 'denied')::boolean, false) is not true then
    raise exception 'FAIL test11: admin_create_agent() was NOT denied for a customer (got %)', v_result;
  end if;

  -- (auth.users is not readable as `authenticated`; test 12 + the owner
  --  assertions below prove the denied call created nothing)
  raise notice 'PASS test11: admin_create_agent denied for customer';
end;
$$;

-- ---------- TEST 12: an admin can create an agent ----------
set "request.jwt.claims" to '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}';

do $$
declare
  v_result jsonb;
  v_role   public.user_role;
begin
  v_result := public.admin_create_agent(
    'authz-new-agent@test.dev', 'AgentTest1!', 'AuthZ New Agent', '9000000004');

  if v_result is null then
    raise exception 'FAIL test12: admin_create_agent() returned null for admin';
  end if;
  if coalesce((v_result ->> 'denied')::boolean, false) is true then
    raise exception 'FAIL test12: admin_create_agent() denied for admin (got %)', v_result;
  end if;

  if coalesce((v_result ->> 'role')::text, '') <> 'agent'
     or coalesce((v_result ->> 'full_name')::text, '') <> 'AuthZ New Agent' then
    raise exception 'FAIL test12: unexpected profile payload (got %)', v_result;
  end if;

  select role into v_role from public.profiles
   where lower(email) = 'authz-new-agent@test.dev';
  if v_role is distinct from 'agent' then
    raise exception 'FAIL test12: created account role is %', coalesce(v_role::text, 'null');
  end if;

  raise notice 'PASS test12: admin created an agent account';
end;
$$;

-- ---------- owner-level audit assertions ----------
-- audit_logs is admin-only under RLS, so the denials written while
-- acting as a customer are asserted here with table-owner privileges.
reset role;

do $$
declare
  v_count integer;
  v_role  public.user_role;
  v_ok    boolean;
begin
  select count(*) into v_count
    from public.audit_logs
   where event_type = 'AUTHORIZATION_FAILED'
     and actor_id = '22222222-2222-2222-2222-222222222222';
  if v_count < 2 then
    raise exception 'FAIL audit: expected cancel_request + dashboard_stats denials (got %)', v_count;
  end if;

  select count(*) into v_count
    from public.audit_logs
   where event_type = 'AUTHORIZATION_FAILED'
     and actor_id = '11111111-1111-1111-1111-111111111111'
     and entity_type = 'profile';
  if v_count < 2 then
    raise exception 'FAIL audit: expected admin_set_role + admin_create_agent denials (got %)', v_count;
  end if;

  select count(*) into v_count
    from public.audit_logs
   where event_type = 'AUTHORIZATION_FAILED'
     and actor_id = '11111111-1111-1111-1111-111111111111'
     and metadata ->> 'action' = 'create_agent';
  if v_count = 0 then
    raise exception 'FAIL audit: admin_create_agent denial was not audited';
  end if;

  select role into v_role from public.profiles
   where id = '33333333-3333-3333-3333-333333333333';
  if v_role is distinct from 'agent' then
    raise exception 'FAIL test10: role changed by a denied call (role=%)', v_role;
  end if;

  -- ---------- test 12 follow-ups (owner can read auth.*) ----------
  -- exactly one account: the denied call in test 11 must not have made one
  select count(*) into v_count
    from auth.users where lower(email) = 'authz-new-agent@test.dev';
  if v_count <> 1 then
    raise exception 'FAIL test11: expected exactly one account, found %', v_count;
  end if;

  select count(*) into v_count
    from public.audit_logs
   where event_type = 'ROLE_CHANGED'
     and actor_id = '44444444-4444-4444-4444-444444444444'
     and metadata ->> 'action' = 'create_agent'
     and metadata ->> 'role' = 'agent';
  if v_count = 0 then
    raise exception 'FAIL audit: agent creation was not audited';
  end if;

  -- the stored password must actually verify, or the agent could never sign in
  select coalesce(
           (select encrypted_password = crypt('AgentTest1!', encrypted_password)
              from auth.users
             where lower(email) = 'authz-new-agent@test.dev'),
           false)
    into v_ok;
  if not v_ok then
    raise exception 'FAIL test12: created agent password does not verify';
  end if;

  select exists (
    select 1 from auth.identities i
      join auth.users u on u.id = i.user_id
     where lower(u.email) = 'authz-new-agent@test.dev'
       and i.provider = 'email'
  ) into v_ok;
  if not v_ok then
    raise exception 'FAIL test12: email identity row is missing (sign-in would fail)';
  end if;

  -- passwords must never reach the audit trail
  select not exists (
    select 1 from public.audit_logs
     where created_at >= now()
       and metadata::text ilike '%AgentTest1%'
  ) into v_ok;
  if not v_ok then
    raise exception 'FAIL audit: password leaked into audit_logs';
  end if;

  raise notice 'PASS audit: AUTHORIZATION_FAILED rows persisted for every denial';
end;
$$;

-- ---------- TEST 13: deleting an account preserves the audit trail ----------
-- The FK is `on delete set null`, which is an UPDATE on the append-only
-- table — 0006 lets that one system update through, nothing else.
do $$
declare
  v_total  integer;
  v_after  integer;
  v_b      integer;
  v_ids    uuid[];
begin
  select count(*) into v_total from public.audit_logs;
  select count(*), array_agg(id)
    into v_b, v_ids
    from public.audit_logs
   where actor_id = '22222222-2222-2222-2222-222222222222';

  if coalesce(v_b, 0) < 2 then
    raise exception 'FAIL test13: expected audit rows for fixture B (got %)', v_b;
  end if;

  delete from public.profiles where id = '22222222-2222-2222-2222-222222222222';

  select count(*) into v_after from public.audit_logs;
  if v_after <> v_total then
    raise exception 'FAIL test13: audit rows lost on account delete (% -> %)', v_total, v_after;
  end if;

  select count(*) into v_after
    from public.audit_logs
   where id = any (v_ids) and actor_id is null;
  if v_after <> v_b then
    raise exception 'FAIL test13: actor_id not unlinked (% of %)', v_after, v_b;
  end if;

  -- …while a direct edit of the same table is still refused
  begin
    update public.audit_logs set event_type = 'HACKED';
    raise exception 'FAIL test13: audit_logs accepted a direct update';
  exception
    when others then
      if sqlstate <> '42501' then
        raise;
      end if;
  end;

  raise notice 'PASS test13: account deleted, audit trail intact and still immutable';
end;
$$;

-- ---------- rollback: no test data persists ----------
rollback;

do $$
begin
  raise notice 'ALL AUTHORIZATION TESTS PASSED (transaction rolled back)';
end;
$$;
