import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import '../data/request_repository.dart';
import '../data/service_repository.dart';
import '../domain/enums.dart';
import '../domain/models.dart';

/// Supabase singletons.
final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);

final requestRepositoryProvider = Provider<RequestRepository>(
  (ref) => RequestRepository(ref.watch(supabaseProvider)),
);

final serviceRepositoryProvider = Provider<ServiceRepository>(
  (ref) => ServiceRepository(ref.watch(supabaseProvider)),
);

/// Emits on sign-in, sign-out and token refresh.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).onAuthStateChange,
);

/// The signed-in user's `profiles` row (role, name, phone).
final profileProvider = FutureProvider<Profile?>((ref) async {
  final auth = ref.watch(authRepositoryProvider);
  final user = auth.currentUser;
  if (user == null) return null;
  // Reload whenever auth changes.
  ref.watch(authStateProvider);
  return auth.fetchProfile(user.id);
});

final userRoleProvider = Provider<UserRole>((ref) {
  final p = ref.watch(profileProvider).value;
  return p?.role ?? UserRole.customer;
});

/// Catalog of active services.
final servicesProvider = FutureProvider<List<ServiceItem>>(
  (ref) => ref.watch(serviceRepositoryProvider).fetchAll(),
);

/// Requests visible to the signed-in user (RLS decides what that means).
final requestsProvider = FutureProvider<List<ServiceRequest>>(
  (ref) async {
    ref.watch(authStateProvider);
    return ref.watch(requestRepositoryProvider).fetchMine();
  },
);

final requestDetailProvider = FutureProvider.family<ServiceRequest, String>(
  (ref, id) => ref.watch(requestRepositoryProvider).fetchById(id),
);

final requestHistoryProvider = FutureProvider.family<List<StatusHistoryEntry>, String>(
  (ref, id) => ref.watch(requestRepositoryProvider).fetchHistory(id),
);

/// Simple client-side summary for the home screen.
final requestSummaryProvider = Provider<RequestSummary>((ref) {
  final all = ref.watch(requestsProvider).value ?? const <ServiceRequest>[];
  int count(RequestStatus s) => all.where((r) => r.status == s).length;
  return RequestSummary(
    total: all.length,
    active: all.where((r) => r.status.isActive).length,
    completed: count(RequestStatus.completed),
    cancelled: count(RequestStatus.cancelled),
  );
});

class RequestSummary {
  const RequestSummary({
    required this.total,
    required this.active,
    required this.completed,
    required this.cancelled,
  });

  final int total;
  final int active;
  final int completed;
  final int cancelled;
}
