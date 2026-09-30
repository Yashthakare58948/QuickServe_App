-- ============================================================
-- QuickServe — tests/authorization_test.sql
-- Backend authorization test (run in the Supabase SQL editor).
--
-- Verifies, at the database layer:
--   1. Customer B cannot SELECT customer A's request
--   2. Customer B cannot UPDATE customer A's request
--   3. cancel_request() by B on A's request is denied (42501)
--      and an AUTHORIZATION_FAILED audit row is written
--   4. dashboard_stats() is denied for non-admins
--   5. A customer cannot INSERT a request on someone else's behalf
--
-- Everything runs inside a transaction that is rolled back, so the
-- project data is left untouched.
-- ============================================================

begin;

-- ---------- test fixtures (as table owner / superuser) ----------
insert into public.profiles (id, email, full_name, role)
values
  ('11111111-1111-1111-1111-111111111111', 'authz-a@test.dev', 'AuthZ Customer A', 'customer'),
  ('22222222-2222-2222-2222-222222222222', 'authz-b@test.dev', 'AuthZ Customer B', 'customer'),
  ('33333333-3333-3333-3333-333333333333', 'authz-agent@test.dev', 'AuthZ Agent', 'agent')
on conflict (id) do nothing;

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

-- ---------- TEST 4: cancel_request RPC denies B and logs AUTHORIZATION_FAILED ----------
do $$
declare
  v_denied boolean := false;
  v_audit  integer;
begin
  begin
    perform public.cancel_request(
      'aaaaaaaa-0000-0000-0000-000000000001',
      'not mine'
    );
  exception
    when insufficient_privilege or check_violation then
      v_denied := true;
    when others then
      if sqlstate = '42501' then
        v_denied := true;
      else
        raise;
      end if;
  end;

  if not v_denied then
    raise exception 'FAIL test4: cancel_request() was NOT denied for customer B';
  end if;

  select count(*) into v_audit
    from public.audit_logs
   where event_type = 'AUTHORIZATION_FAILED'
     and actor_id = '22222222-2222-2222-2222-222222222222';

  if v_audit = 0 then
    raise exception 'FAIL test4: AUTHORIZATION_FAILED was not audited';
  end if;

  raise notice 'PASS test4: cancel_request denied for B and AUTHORIZATION_FAILED audited';
end;
$$;

-- ---------- TEST 5: dashboard_stats() denied for non-admin ----------
do $$
declare
  v_denied boolean := false;
begin
  begin
    perform public.dashboard_stats();
  exception
    when others then
      if sqlstate = '42501' then
        v_denied := true;
      else
        raise;
      end if;
  end;

  if not v_denied then
    raise exception 'FAIL test5: dashboard_stats() allowed for a customer';
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

-- ---------- TEST 8: customer A still sees her own request ----------
set "request.jwt.claims" to '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
    from public.service_requests
   where id = 'aaaaaaaa-0000-0000-0000-000000000001';

  if v_count <> 1 then
    raise exception 'FAIL test8: owner cannot see her own request (rows=%)', v_count;
  end if;
  raise notice 'PASS test8: customer A can SELECT her own request';
end;
$$;

-- ---------- rollback: no test data persists ----------
reset role;
rollback;

do $$
begin
  raise notice 'ALL AUTHORIZATION TESTS PASSED (transaction rolled back)';
end;
$$;
