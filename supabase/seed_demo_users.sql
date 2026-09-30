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
-- ============================================================
create extension if not exists pgcrypto;

do $$
declare
  v_customer_id uuid := gen_random_uuid();
  v_agent_id    uuid := gen_random_uuid();
  v_admin_id    uuid := gen_random_uuid();
begin
  -- ---------- auth.users ----------
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, invited_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) values
    ('00000000-0000-0000-0000-000000000000', v_customer_id, 'authenticated', 'authenticated',
     'customer@demo.dev', crypt('Demo@12345', gen_salt('bf')),
     now(), null, '{"provider":"email","providers":["email"]}',
     '{"full_name":"Aarav Customer"}', now(), now()),
    ('00000000-0000-0000-0000-000000000000', v_agent_id, 'authenticated', 'authenticated',
     'agent@demo.dev', crypt('Demo@12345', gen_salt('bf')),
     now(), null, '{"provider":"email","providers":["email"]}',
     '{"full_name":"Sneha Agent"}', now(), now()),
    ('00000000-0000-0000-0000-000000000000', v_admin_id, 'authenticated', 'authenticated',
     'admin@demo.dev', crypt('Demo@12345', gen_salt('bf')),
     now(), null, '{"provider":"email","providers":["email"]}',
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
end;
$$;
