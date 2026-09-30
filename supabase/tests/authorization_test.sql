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
   now(), '{"provider":"email","providers":["email"]}', '{"full_name":"AuthZ Agent"}', now(), now())
on conflict (id) do nothing;

-- promote the third fixture user to agent (owner context: guard allows it)
update public.profiles
   set role = 'agent', full_name = 'AuthZ Agent'
 where id = '33333333-3333-3333-3333-333333333333';

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

-- ---------- owner-level audit assertions ----------
-- audit_logs is admin-only under RLS, so the denials written while
-- acting as a customer are asserted here with table-owner privileges.
reset role;

do $$
declare
  v_count integer;
  v_role  public.user_role;
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
  if v_count = 0 then
    raise exception 'FAIL audit: admin_set_role denial was not audited';
  end if;

  select role into v_role from public.profiles
   where id = '33333333-3333-3333-3333-333333333333';
  if v_role is distinct from 'agent' then
    raise exception 'FAIL test10: role changed by a denied call (role=%)', v_role;
  end if;

  raise notice 'PASS audit: AUTHORIZATION_FAILED rows persisted for every denial';
end;
$$;

-- ---------- rollback: no test data persists ----------
rollback;

do $$
begin
  raise notice 'ALL AUTHORIZATION TESTS PASSED (transaction rolled back)';
end;
$$;
