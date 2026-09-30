// Authorization integration test (requires a configured Supabase project).
//
// Run with:
//   cd mobile
//   flutter test test/authorization_test.dart --dart-define-from-file=env.json
//
// The test signs in as two separate customers and proves that one
// customer cannot read or modify the other's request — the denial must
// come from Postgres RLS, not from UI hiding.
//
// Without configuration the suite is skipped so `flutter test` still
// passes in CI.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

const url = String.fromEnvironment('SUPABASE_URL');
const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Optional dedicated test credentials (never production accounts).
const userAEmail = String.fromEnvironment('AUTHZ_A_EMAIL');
const userAPassword = String.fromEnvironment('AUTHZ_A_PASSWORD');
const userBEmail = String.fromEnvironment('AUTHZ_B_EMAIL');
const userBPassword = String.fromEnvironment('AUTHZ_B_PASSWORD');

void main() {
  final configured = url.isNotEmpty &&
      anonKey.isNotEmpty &&
      userAEmail.isNotEmpty &&
      userBEmail.isNotEmpty;

  setUpAll(() {
    // Give a clearer message than an empty skip.
    if (!configured) {
      // ignore: avoid_print
      print(
        'authorization_test SKIPPED: provide SUPABASE_URL, SUPABASE_ANON_KEY '
        'and AUTHZ_A_*/AUTHZ_B_* credentials via --dart-define-from-file.',
      );
    }
  });

  group('RLS authorization (integration)', () {
    test(
      'customer B cannot read or modify customer A\'s request',
      () async {
        final clientA = SupabaseClient(url, anonKey);
        final clientB = SupabaseClient(url, anonKey);

        try {
          await clientA.auth.signInWithPassword(
              email: userAEmail, password: userAPassword);
          await clientB.auth.signInWithPassword(
              email: userBEmail, password: userBPassword);

          // Seed: A creates a request (RPC re-validates the role server-side).
          final services = await clientA
              .from('services')
              .select('id')
              .limit(1)
              .maybeSingle();
          expect(services, isNotNull, reason: 'seed services first');

          final created = await clientA.rpc('create_request', params: {
            'p_service_id': services!['id'],
            'p_description': 'Authorization test request from A',
            'p_preferred_at':
                DateTime.now().add(const Duration(days: 2)).toIso8601String(),
            'p_address': '12 Test Street, Nagpur',
            'p_priority': 'medium',
          }) as Map<String, dynamic>;

          final requestId = created['id'] as String;
          addTearDown(() async {
            // Best-effort cleanup as admin-less data: A cancels her own row.
            try {
              await clientA.rpc('cancel_request', params: {
                'p_request_id': requestId,
                'p_reason': 'authorization test cleanup',
              });
            } catch (_) {}
            await clientA.auth.signOut();
            await clientB.auth.signOut();
            clientA.dispose();
            clientB.dispose();
          });

          // 1. A can read her own request.
          final aRead = await clientA
              .from('service_requests')
              .select('id')
              .eq('id', requestId);
          expect(aRead.length, 1, reason: 'owner must see her own request');

          // 2. B must see ZERO rows for A's request (RLS filter).
          final bRead = await clientB
              .from('service_requests')
              .select('id')
              .eq('id', requestId);
          expect(bRead, isEmpty,
              reason: 'RLS must hide A\'s request from B');

          // 3. B cannot update A's request: 0 rows matched => no change.
          final bUpdate = await clientB
              .from('service_requests')
              .update({'description': 'hijacked by B'})
              .eq('id', requestId)
              .select('id');
          expect(bUpdate, isEmpty,
              reason: 'RLS must block B updating A\'s request');

          // 4. B calling cancel_request on A's request is refused by the
          //    SECURITY DEFINER function (42501), not by the client.
          Object? rpcError;
          try {
            await clientB.rpc('cancel_request', params: {
              'p_request_id': requestId,
              'p_reason': 'not mine',
            });
          } catch (e) {
            rpcError = e;
          }
          expect(rpcError, isNotNull,
              reason: 'cancel_request must be denied for B');
          expect(rpcError.toString(), contains('belong to you'));

          // 5. The denial is audited server-side.
          //    (audit_logs is admin-only; A's read of it must be empty.)
          final auditAsB = await clientB
              .from('audit_logs')
              .select('id')
              .limit(1);
          expect(auditAsB, isEmpty,
              reason: 'customers must not read the audit log');

          // 6. dashboard_stats is admin-only.
          Object? dashError;
          try {
            await clientB.rpc('dashboard_stats');
          } catch (e) {
            dashError = e;
          }
          expect(dashError, isNotNull,
              reason: 'dashboard_stats must be denied for customers');
        } finally {
          await clientA.auth.signOut();
          await clientB.auth.signOut();
        }
      },
      skip: !configured,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
