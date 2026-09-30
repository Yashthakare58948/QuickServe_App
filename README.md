# QuickServe — Service Request Management

[![CI](https://github.com/Yashthakare58948/QuickServe_App/actions/workflows/ci.yml/badge.svg)](https://github.com/Yashthakare58948/QuickServe_App/actions/workflows/ci.yml)

End-to-end service-request platform built for the **SWASIQ Intern Technical
Assignment**. Customers create and track service requests from a Flutter mobile
app, service agents manage assigned work, and administrators operate everything
through a web portal — all backed by Supabase (Postgres + Auth + Row Level
Security).

```
┌────────────┐   ┌────────────────┐   ┌──────────────────────────────┐
│ Flutter app│   │ Next.js portal │   │ Supabase                     │
│ (customer/ │   │ (admin only)   │   │  Auth  · Postgres + RLS      │
│  agent)    │─▶│                │─▶│  RPCs (SECURITY DEFINER)      │
└────────────┘   └────────────────┘   └──────────────────────────────┘
```

## Technology stack

| Layer      | Technology |
|------------|------------|
| Mobile     | Flutter 3.x, Riverpod, go_router, supabase_flutter |
| Web portal | Next.js 16 (App Router), TypeScript, Tailwind CSS, @supabase/ssr |
| Backend    | Supabase — Postgres 16, Auth, RLS, SECURITY DEFINER RPCs |
| Quality    | flutter test, ESLint, GitHub Actions CI |

## Repository structure

```
├── mobile/        Flutter app (Android/iOS target: Android APK)
├── admin/         Next.js administration portal
├── supabase/
│   ├── migrations/    versioned SQL: schema → RLS → functions → seed
│   ├── tests/         authorization_test.sql (backend RBAC tests)
│   └── seed_demo_users.sql
├── docs/          architecture, database and security documentation
└── .github/workflows/ci.yml
```

## Setup

### 1. Backend (Supabase)

**Option A — Supabase CLI (used for this build):**

```bash
supabase login --token <access-token>
supabase link --project-ref <project-ref>
supabase db push                   # applies 0001 → 0006 in order
```

Then apply `supabase/seed_demo_users.sql` once (SQL editor, or any Postgres
client) to create the demo accounts.

**Option B — SQL editor:** create a project, then run, **in order**:

1. `supabase/migrations/0001_schema.sql`
2. `supabase/migrations/0002_rls_policies.sql`
3. `supabase/migrations/0003_functions.sql`
4. `supabase/migrations/0004_seed_services.sql`
5. `supabase/migrations/0005_admin_create_agent.sql`
6. `supabase/migrations/0006_append_only_fk_unlink.sql`
7. `supabase/seed_demo_users.sql` (once)

Then copy the **Project URL** and **anon key** from *Project Settings → API*
into `mobile/env.json` and `admin/.env.local`.

> No secrets live in this repository. The anon key is public-by-design but is
> still supplied through environment configuration, never hard-coded.

### 2. Flutter app

```bash
cd mobile
cp env.example.json env.json          # then paste your URL + anon key
flutter pub get
flutter run --dart-define-from-file=env.json
```

Release APK:

```bash
flutter build apk --release --dart-define-from-file=env.json
# output: build/app/outputs/flutter-apk/app-release.apk
```

### 3. Admin portal

```bash
cd admin
cp .env.example .env.local            # then paste your URL + anon key
npm install
npm run dev                           # http://localhost:3000
```

## Test credentials

Created by `supabase/seed_demo_users.sql` — all use password **`Demo@12345`**.

| Role    | Email              | Portal | Mobile app |
|---------|--------------------|--------|------------|
| Customer| customer@demo.dev  | –      | ✓          |
| Agent   | agent@demo.dev     | –      | ✓          |
| Admin   | admin@demo.dev     | ✓      | –          |

The admin can add more agents in the portal (**Service agents → Add agent**) or
promote an existing customer (**Customers → Promote to agent**).

## Testing

```bash
# Flutter unit/widget tests
cd mobile && flutter test

# Authorization integration test (needs env.json + two extra test accounts)
flutter test test/authorization_test.dart --dart-define-from-file=env.json

# Backend RBAC tests (13 assertions) — run supabase/tests/authorization_test.sql
# in the SQL editor, or against the database with any Postgres client.
# Everything is rolled back afterwards.

# Admin portal lint + build
cd admin && npm run lint && npm run build
```

The backend test proves at minimum that **a customer cannot access another
customer's request** (SELECT/UPDATE/RPC all denied, with an
`AUTHORIZATION_FAILED` audit row written).

## Documentation

- [Architecture](docs/architecture.md) — components, data flow, diagram
- [Database](docs/database.md) — tables, relationships, indexes, constraints
- [Security](docs/security.md) — RBAC matrix, RLS policies, audit events

## Feature checklist

- [x] Flutter app: splash, login, registration, home, services, create request,
      my requests, request details, profile, logout
- [x] `REQ-YYYY-NNNNNN` unique request ids generated in the database
- [x] Request lifecycle `CREATED → ASSIGNED → ACCEPTED → IN_PROGRESS → COMPLETED`
      (+ `CANCELLED` where eligible), enforced server-side
- [x] Admin portal: dashboard counters, search/filter/pagination, assign agent,
      status updates, customer/agent views, audit log
- [x] Agent staffing: create new agent accounts and promote/demote users from
      the portal
- [x] Roles: customer, agent, admin — enforced by Postgres RLS + RPC checks
- [x] Session persistence, password reset
- [x] Audit trail (`LOGIN_SUCCESS`, `REQUEST_CREATED`, `REQUEST_ASSIGNED`,
      `REQUEST_UPDATED`, `AUTHORIZATION_FAILED`, …) — no secrets ever logged
- [x] Error handling: validation, network failures, backend errors, denied actions
- [x] Tests: Flutter unit/widget, backend authorization test, integration authz test
- [x] CI: analyze + test + lint + build on every push
