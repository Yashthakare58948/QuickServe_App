# QuickServe — Security Model

## Principle

**The client is never trusted.** Every sensitive operation is enforced twice:
once by Row Level Security (row visibility/mutations) and once by
`SECURITY DEFINER` RPCs (role + state-machine checks). Hiding UI buttons is
convenience, not security.

## Roles

| Role | How obtained |
|------|--------------|
| `customer` | Default at signup (profile trigger) |
| `agent` | Created by an admin via `admin_create_agent()`, or promoted from `customer` via `admin_set_role()` |
| `admin` | Promoted by an admin; cannot demote themselves |

## RBAC matrix

| Capability | Customer | Agent | Admin |
|---|---|---|---|
| Create request | ✅ (as self only) | ❌ | ✅ |
| View own requests | ✅ | ✅ (assigned) | ✅ (all) |
| View all requests | ❌ | ❌ | ✅ |
| Accept / start / complete | ❌ | ✅ (assigned rows only) | ✅ |
| Cancel (eligible) | ✅ (own, `created`/`assigned`) | ❌ | ✅ |
| Add note | ✅ (own) | ✅ (assigned) | ✅ |
| Assign agent | ❌ | ❌ | ✅ |
| Create agent account | ❌ | ❌ | ✅ |
| Change user roles | ❌ | ❌ | ✅ |
| View dashboard stats | ❌ | ❌ | ✅ |
| View audit log | ❌ | ❌ | ✅ |
| Manage services | ❌ | ❌ | ✅ |

## RLS policies (0002_rls_policies.sql)

### `service_requests`
- `SELECT` — `customer_id = auth.uid()` **or** `agent_id = auth.uid()` **or**
  `is_admin()`.
- `INSERT` — customer may insert only rows where `customer_id = auth.uid()`,
  `status = 'created'`, `agent_id IS NULL`.
- `UPDATE` — own row (customer) / assigned row (agent) / any row (admin);
  `WITH CHECK` prevents re-pointing ownership.
- No `DELETE` policy → nobody deletes requests.

### `profiles`
- Self read/update; admins read/update everyone.
- Cross-reads are narrowly scoped: an agent sees only customers who have a
  request assigned to them; a customer sees only the agent assigned to their
  request.
- A trigger blocks non-admin role changes even if a policy allowed the row.

### `services`
Read for authenticated users, write for admins.

### `request_status_history`
Read for admins and for participants of that request. **No INSERT policy** —
only `SECURITY DEFINER` functions/triggers can append.

### `audit_logs`
Read for admins only; insert only through `log_event()` / internal functions.
UPDATE/DELETE blocked by an append-only trigger — with one narrow exception:
the FK's own `ON DELETE SET NULL` when an account is removed (it runs inside
the foreign-key trigger, `pg_trigger_depth() > 1`). The audit row survives with
`actor_id = null`; a direct `UPDATE` from any client still fails with `42501`.

### `anon`
All table privileges revoked — no session, no data. The only application RPC
it may execute is `log_event()`, and that accepts just the pre-auth events
`LOGIN_FAILED` and `PASSWORD_RESET_REQUESTED`; every other event raises `401`,
and all business RPCs (`create_request`, `assign_agent`, …) are revoked.

## Defense in depth (RPC layer)

Even if a policy were misconfigured, every RPC re-validates:

1. `auth.uid()` must exist (else `401`).
2. `current_user_role()` must permit the action — otherwise the RPC **returns**
   `{"denied": true, "message": …}` *and* writes an `AUTHORIZATION_FAILED` audit
   row. Denials are *returned*, not `RAISE`d: an exception would roll back the
   whole PostgREST transaction and take the audit row with it. Validation and
   state-machine errors still `RAISE` (nothing to audit there), and direct table
   writes are still blocked by RLS/guard triggers with `42501`.
3. Input validation (lengths, future date, active service, agent role).
4. State-machine validation via `is_valid_transition()`; terminal states are
   frozen.
5. History + audit appended in the same transaction.

Both clients unwrap the denial object (`RequestRepository._unwrap` /
`rpcDenial()`), turn the `message` into a normal user-facing error and never
report success on a denied call. Internal helpers (`deny`, `record_transition`,
guard triggers) have `EXECUTE` revoked from clients.

Helper functions (`current_user_role`, `is_admin`) are `SECURITY DEFINER` with
a pinned `search_path` to avoid policy recursion, and `EXECUTE` is revoked from
`anon`/`public`.

### Account provisioning (`admin_create_agent`)

The admin portal can create agent accounts without ever touching the
service-role key: `admin_create_agent(email, password, full_name, phone?)` is a
`SECURITY DEFINER` RPC that

- refuses non-admins with the standard `{denied: true}` object + audit row,
- validates email / 8+ char password / name, and rejects duplicate emails
  (`23505`) before writing anything,
- inserts the `auth.users` + `auth.identities` rows the same way the demo seed
  does (verified in test 12 that the stored hash actually checks out), and
- writes `ROLE_CHANGED` with `action: "create_agent"` — **never the password**.

Because the account is created already confirmed, the agent can sign in
immediately (there is no invitation email). Customers still self-register.

## Authentication

- Email + password via Supabase Auth (min 6 chars server-side; 8+ enforced
  client-side).
- Sessions persisted by `supabase_flutter` (secure storage) and by
  `@supabase/ssr` cookies on the web.
- Password reset: `resetPasswordForEmail` links (both clients).
- Portal middleware additionally requires `role = 'admin'` for page access —
  but RLS remains the enforcement point.

## Audit trail

| Event | When |
|-------|------|
| `LOGIN_SUCCESS` / `LOGIN_FAILED` / `LOGOUT` | auth lifecycle |
| `REGISTER_SUCCESS` / `PASSWORD_RESET_REQUESTED` | account actions |
| `REQUEST_CREATED` / `REQUEST_ASSIGNED` / `REQUEST_UPDATED` / `REQUEST_CANCELLED` | request lifecycle |
| `ROLE_CHANGED` / `PROFILE_UPDATED` | admin/profile actions |
| `AUTHORIZATION_FAILED` | any denied capability (with attempted action) |
| `DATABASE_ERROR` | surfaced client failures |

`event_type` is whitelisted inside `log_event()` — clients cannot write
arbitrary rows. `LOGIN_FAILED` and `PASSWORD_RESET_REQUESTED` are additionally
allowed for `anon`, so a failed sign-in on either client (or a non-admin
hitting the portal middleware) is still recorded without a session. Metadata is
size- and content-limited by convention: **passwords, tokens, API keys and
emails are never logged**, and the logger redacts sensitive keys before
printing to the console.

## Secrets & configuration

- Nothing sensitive is committed (`.gitignore` covers `.env*`, `env.json`,
  keystores, keys).
- Mobile: `--dart-define-from-file=env.json`; web: `.env.local` — both
  gitignored, both documented in `.env.example`.
- The anon/public key is safe to ship in clients **because** RLS protects the
  data; the service-role key is never used by either client.

## Verifying

- `supabase/tests/authorization_test.sql` — 13 backend assertions (cross-customer
  SELECT/UPDATE, RPC denial objects for `cancel_request`/`dashboard_stats`/
  `admin_set_role`/`admin_create_agent`, `AUTHORIZATION_FAILED` audit rows,
  blocked self-promotion, admin-only stats, agent visibility, admin agent
  provisioning incl. password verification and no-password-in-audit, account
  deletion preserving the audit trail), rolled back afterwards.
- `mobile/test/authorization_test.dart` — live integration test: customer B
  reads/updates/cancels customer A's request → all denied by the backend.
