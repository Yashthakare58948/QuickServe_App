import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/enums.dart';
import '../../domain/models.dart';

/// Data access for `service_requests` + `request_status_history`.
///
/// All queries run as the signed-in user; row visibility and writes are
/// enforced by Postgres RLS and the SECURITY DEFINER RPCs.
class RequestRepository {
  RequestRepository(this._client);

  final SupabaseClient _client;

  static const _join = '''
    id, request_id, customer_id, agent_id, service_id, description,
    preferred_at, address, priority, status, cancel_reason,
    created_at, updated_at,
    services(id, name),
    customer:profiles!service_requests_customer_id_fkey(id, full_name),
    agent:profiles!service_requests_agent_id_fkey(id, full_name)
  ''';

  /// The customer's own requests (RLS: `customer_id = auth.uid()`).
  Future<List<ServiceRequest>> fetchMine() async {
    final rows = await _client
        .from('service_requests')
        .select(_join)
        .order('created_at', ascending: false);
    return rows.map(ServiceRequest.fromJson).toList();
  }

  /// Requests assigned to the signed-in agent (RLS: `agent_id = auth.uid()`).
  Future<List<ServiceRequest>> fetchAssigned() async {
    final rows = await _client
        .from('service_requests')
        .select(_join)
        .order('created_at', ascending: false);
    return rows.map(ServiceRequest.fromJson).toList();
  }

  Future<ServiceRequest> fetchById(String id) async {
    final row = await _client
        .from('service_requests')
        .select(_join)
        .eq('id', id)
        .maybeSingle();
    if (row == null) {
      throw const AppException('Request not found.', kind: AppErrorKind.notFound);
    }
    return ServiceRequest.fromJson(row);
  }

  Future<List<StatusHistoryEntry>> fetchHistory(String requestId) async {
    final rows = await _client
        .from('request_status_history')
        .select('''
          from_status, to_status, note, created_at,
          changed_by_user:profiles!request_status_history_changed_by_fkey(full_name)
        ''')
        .eq('request_id', requestId)
        .order('created_at');
    return rows.map(StatusHistoryEntry.fromJson).toList();
  }

  /// RPCs return `{"denied": true, "message": ...}` when the server-side
  /// authorization check fails (the row is already audited server-side).
  /// Anything else is the success payload (the RPC never raises for auth).
  static Map<String, dynamic> _unwrap(Object? result) {
    final row = result is Map<String, dynamic>
        ? result
        : (result as Map).cast<String, dynamic>();
    if (row['denied'] == true) {
      throw AppException(
        (row['message'] as String?) ?? 'You are not allowed to do that.',
        kind: AppErrorKind.forbidden,
      );
    }
    return row;
  }

  Future<ServiceRequest> create({
    required String serviceId,
    required String description,
    required DateTime preferredAt,
    required String address,
    required RequestPriority priority,
  }) async {
    final row = _unwrap(await _client.rpc('create_request', params: {
      'p_service_id': serviceId,
      'p_description': description.trim(),
      'p_preferred_at': preferredAt.toUtc().toIso8601String(),
      'p_address': address.trim(),
      'p_priority': priority.raw,
    }));
    await AppLogger.event('REQUEST_CREATED',
        entityType: 'service_request', entityId: row['id'] as String?);
    return ServiceRequest.fromJson(row);
  }

  Future<ServiceRequest> updateStatus({
    required String requestId,
    required RequestStatus to,
    String? note,
  }) async {
    final row = _unwrap(await _client.rpc('update_request_status', params: {
      'p_request_id': requestId,
      'p_new_status': to.raw,
      'p_note': note,
    }));
    await AppLogger.event('REQUEST_UPDATED',
        entityType: 'service_request',
        entityId: requestId,
        data: {'status': to.raw});
    return ServiceRequest.fromJson(row);
  }

  Future<ServiceRequest> cancel({required String requestId, String? reason}) async {
    final row = _unwrap(await _client.rpc('cancel_request', params: {
      'p_request_id': requestId,
      'p_reason': reason,
    }));
    await AppLogger.event('REQUEST_CANCELLED',
        entityType: 'service_request', entityId: requestId);
    return ServiceRequest.fromJson(row);
  }

  Future<void> addNote({required String requestId, required String note}) async {
    _unwrap(await _client.rpc('add_note', params: {
      'p_request_id': requestId,
      'p_note': note.trim(),
    }));
    await AppLogger.event('REQUEST_UPDATED',
        entityType: 'service_request',
        entityId: requestId,
        data: {'action': 'add_note'});
  }
}
