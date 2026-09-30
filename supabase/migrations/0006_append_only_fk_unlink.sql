-- ============================================================
-- QuickServe — 0006_audit_fk_unlink.sql
-- Fix: audit_logs.actor_id / request_status_history.changed_by are
-- `on delete set null`, but the append-only trigger rejects EVERY
-- update — including the FK's own null-out. Net effect before this
-- migration: an account with any audit row could never be deleted
-- ("Table audit_logs is append-only" on a plain user delete).
--
-- Fix: allow UPDATEs that arrive from inside a trigger (Postgres
-- runs foreign-key actions as triggers, so pg_trigger_depth() > 1).
-- A direct `update ... set event_type = ...` is still issued at depth
-- 1 and still raises 42501 — audit rows remain immutable to SQL.
-- ============================================================

create or replace function public.prevent_mutation()
returns trigger
language plpgsql
as $$
begin
  -- ON DELETE SET NULL fires as an RI trigger; let that unlink through
  -- so the audit row survives with actor_id = null ("Anonymous").
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1 then
    return new;
  end if;

  raise exception 'Table % is append-only', tg_table_name
    using errcode = '42501';
end;
$$;

-- grants are unaffected by create or replace (EXECUTE stays revoked
-- from public/anon/authenticated — see 0003_functions.sql).
