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
| `agent` | Promoted by an admin via `admin_set_role()` |
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
UPDATE/DELETE blocked by an append-only trigger.

### `anon`
All privileges revoked — no session, no data.

## Defense in depth (RPC layer)

Even if a policy were misconfigured, every RPC re-validates:

1. `auth.uid()` must exist (else `401`).
2. `current_user_role()` must permit the action — else the call is denied
   **and** an `AUTHORIZATION_FAILED` audit row is written.
3. Input validation (lengths, future date, active service, agent role).
4. State-machine validation via `is_valid_transition()`; terminal states are
   frozen.
5. History + audit appended in the same transaction.

Helper functions (`current_user_role`, `is_admin`) are `SECURITY DEFINER` with
a pinned `search_path` to avoid policy recursion, and `EXECUTE` is revoked from
`anon`/`public`.

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
arbitrary rows. Metadata is size- and content-limited by convention:
**passwords, tokens, API keys and emails are never logged**, and the logger
redacts sensitive keys before printing to the console.

## Secrets & configuration

- Nothing sensitive is committed (`.gitignore` covers `.env*`, `env.json`,
  keystores, keys).
- Mobile: `--dart-define-from-file=env.json`; web: `.env.local` — both
  gitignored, both documented in `.env.example`.
- The anon/public key is safe to ship in clients **because** RLS protects the
  data; the service-role key is never used by either client.

## Verifying

- `supabase/tests/authorization_test.sql` — 8 backend assertions (cross-customer
  SELECT/UPDATE/RPC denials, audit write, admin-only stats, agent visibility),
  rolled back afterwards.
- `mobile/test/authorization_test.dart` — live integration test: customer B
  reads/updates/cancels customer A's request → all denied by the backend.
