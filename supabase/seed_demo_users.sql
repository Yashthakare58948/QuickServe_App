-- ============================================================
-- QuickServe — seed_demo_users.sql
-- Run ONCE in the Supabase SQL editor (NOT part of migrations).
-- Creates three demo accounts documented in the README.
--
--   customer@demo.dev / Demo@12345
--   agent@demo.dev    / Demo@12345
--   admin@demo.dev    / Demo@12345
--
-- NOTE: demo passwords are public test credentials for this
-- assignment only. Never reuse them anywhere else.
--
-- Safe to re-run: existing accounts are detected, their roles are
-- re-asserted and their token columns re-normalised.
-- ============================================================
create extension if not exists pgcrypto;

do $$
declare
  v_customer_id uuid := gen_random_uuid();
  v_agent_id    uuid := gen_random_uuid();
  v_admin_id    uuid := gen_random_uuid();
begin
  if exists (
    select 1 from auth.users
     where email in ('customer@demo.dev', 'agent@demo.dev', 'admin@demo.dev')
  ) then
    raise notice 'demo users already exist — re-asserting roles';
  else
    -- ---------- auth.users ----------
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, confirmation_sent_at, invited_at,
      confirmation_token, recovery_token, email_change,
      email_change_token_new, email_change_token_current,
      reauthentication_token, phone_change, phone_change_token,
      raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    ) values
      ('00000000-0000-0000-0000-000000000000', v_customer_id, 'authenticated', 'authenticated',
       'customer@demo.dev', crypt('Demo@12345', gen_salt('bf')),
       now(), now(), null, '', '', '', '', '', '', '', '',
       '{"provider":"email","providers":["email"]}',
       '{"full_name":"Aarav Customer"}', now(), now()),
      ('00000000-0000-0000-0000-000000000000', v_agent_id, 'authenticated', 'authenticated',
       'agent@demo.dev', crypt('Demo@12345', gen_salt('bf')),
       now(), now(), null, '', '', '', '', '', '', '', '',
       '{"provider":"email","providers":["email"]}',
       '{"full_name":"Sneha Agent"}', now(), now()),
      ('00000000-0000-0000-0000-000000000000', v_admin_id, 'authenticated', 'authenticated',
       'admin@demo.dev', crypt('Demo@12345', gen_salt('bf')),
       now(), now(), null, '', '', '', '', '', '', '', '',
       '{"provider":"email","providers":["email"]}',
       '{"full_name":"Ravi Admin"}', now(), now());

    -- ---------- identities (required by newer Supabase Auth versions) ----------
    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) values
      (gen_random_uuid(), v_customer_id, v_customer_id::text,
       jsonb_build_object('sub', v_customer_id::text, 'email', 'customer@demo.dev', 'email_verified', true),
       'email', now(), now(), now()),
      (gen_random_uuid(), v_agent_id, v_agent_id::text,
       jsonb_build_object('sub', v_agent_id::text, 'email', 'agent@demo.dev', 'email_verified', true),
       'email', now(), now(), now()),
      (gen_random_uuid(), v_admin_id, v_admin_id::text,
       jsonb_build_object('sub', v_admin_id::text, 'email', 'admin@demo.dev', 'email_verified', true),
       'email', now(), now(), now());

    -- ---------- roles (profiles rows are auto-created by trigger) ----------
    update public.profiles set role = 'agent', full_name = 'Sneha Agent', phone = '9000000002'
      where id = v_agent_id;
    update public.profiles set role = 'admin', full_name = 'Ravi Admin',  phone = '9000000003'
      where id = v_admin_id;
    update public.profiles set full_name = 'Aarav Customer', phone = '9000000001'
      where id = v_customer_id;
  end if;

  -- ---------- normalise token columns ----------
  -- Supabase Auth reads these columns into non-nullable Go strings.
  -- A NULL here makes every password sign-in fail with
  -- "Database error querying schema", so keep them '' like Auth does.
  update auth.users
     set confirmation_token         = coalesce(confirmation_token, ''),
         recovery_token             = coalesce(recovery_token, ''),
         email_change               = coalesce(email_change, ''),
         email_change_token_new     = coalesce(email_change_token_new, ''),
         email_change_token_current = coalesce(email_change_token_current, ''),
         reauthentication_token     = coalesce(reauthentication_token, ''),
         phone_change               = coalesce(phone_change, ''),
         phone_change_token         = coalesce(phone_change_token, ''),
         confirmation_sent_at       = coalesce(confirmation_sent_at, email_confirmed_at)
   where email in ('customer@demo.dev', 'agent@demo.dev', 'admin@demo.dev');
end;
$$;
