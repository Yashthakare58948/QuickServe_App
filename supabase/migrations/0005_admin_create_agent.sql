-- ============================================================
-- QuickServe — 0005_admin_create_agent.sql
-- Lets an admin provision new agent accounts from the portal.
--
-- Why a SECURITY DEFINER RPC instead of `auth.admin.createUser`:
-- the portal ships only the anon key and the service-role key must
-- never reach a browser. This function runs as its owner (postgres),
-- performs the same auth.users + auth.identities insert the demo
-- seed does, and still refuses the call — WITH an audit row — unless
-- the calling session is an admin.
--
-- The password is never stored in the audit log or returned.
-- ============================================================

create extension if not exists pgcrypto;

create or replace function public.admin_create_agent(
  p_email     text,
  p_password  text,
  p_full_name text,
  p_phone     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_role  public.user_role := public.current_user_role();
  v_email text := lower(trim(coalesce(p_email, '')));
  v_name  text := trim(coalesce(p_full_name, ''));
  v_id    uuid;
  v_row   public.profiles;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '401';
  end if;
  if v_role is distinct from 'admin' then
    return public.deny('create_agent', 'Admins only', 'profile');
  end if;

  -- ---------- validation (RAISE: nothing to audit) ----------
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid email address' using errcode = '22023';
  end if;
  if char_length(coalesce(p_password, '')) < 8 then
    raise exception 'Password must be at least 8 characters' using errcode = '22023';
  end if;
  if char_length(v_name) < 2 then
    raise exception 'Full name must be at least 2 characters' using errcode = '22023';
  end if;
  if exists (select 1 from auth.users where lower(email) = v_email)
     or exists (select 1 from public.profiles where lower(email) = v_email) then
    raise exception 'An account with this email already exists' using errcode = '23505';
  end if;

  v_id := gen_random_uuid();

  -- ---------- auth.users (all token columns non-NULL: GoTrue reads them) ----------
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, confirmation_sent_at,
    confirmation_token, recovery_token, email_change,
    email_change_token_new, email_change_token_current,
    reauthentication_token, phone_change, phone_change_token,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    v_email, crypt(p_password, gen_salt('bf')),
    now(), now(),
    '', '', '', '', '', '', '', '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', v_name),
    now(), now()
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), v_id, v_id::text,
    jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
    'email', now(), now(), now()
  );

  -- ---------- profile: created by the signup trigger, promoted here ----------
  update public.profiles
     set role      = 'agent',
         full_name = v_name,
         email     = v_email,
         phone     = nullif(trim(coalesce(p_phone, '')), '')
   where id = v_id
   returning * into v_row;

  if not found then
    raise exception 'Profile was not created for this account' using errcode = 'P0002';
  end if;

  -- ---------- audit (metadata carries the email, never the password) ----------
  insert into public.audit_logs (actor_id, actor_role, event_type, entity_type, entity_id, metadata)
  values (v_uid, v_role, 'ROLE_CHANGED', 'profile', v_id::text,
          jsonb_build_object('role', 'agent', 'action', 'create_agent', 'email', v_email));

  return to_jsonb(v_row);
end;
$$;

-- ---------- execute grants: session admins only ----------
revoke all on function public.admin_create_agent(text, text, text, text) from public, anon;
grant execute on function public.admin_create_agent(text, text, text, text) to authenticated;
