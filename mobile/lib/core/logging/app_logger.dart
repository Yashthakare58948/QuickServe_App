import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Application logger.
///
/// * Local console output is redacted — passwords, tokens and keys are
///   never printed (see [_redact]).
/// * Meaningful business events are persisted to `audit_logs` through the
///   `log_event` RPC, which whitelists event types server-side.
class AppLogger {
  AppLogger._();

  static const _sensitiveKeys = {
    'password',
    'token',
    'access_token',
    'refresh_token',
    'apikey',
    'api_key',
    'secret',
    'key',
    'authorization',
    'email', // emails are personal data; keep them out of console logs
  };

  /// Events that are allowed to be persisted (mirrors the DB whitelist).
  static const persistedEvents = {
    'LOGIN_SUCCESS',
    'LOGIN_FAILED',
    'LOGOUT',
    'REGISTER_SUCCESS',
    'PASSWORD_RESET_REQUESTED',
    'REQUEST_CREATED',
    'REQUEST_ASSIGNED',
    'REQUEST_UPDATED',
    'REQUEST_CANCELLED',
    'PROFILE_UPDATED',
    'AUTHORIZATION_FAILED',
    'DATABASE_ERROR',
  };

  static Map<String, dynamic> _redact(Map<String, dynamic>? data) {
    if (data == null) return const {};
    return data.map((key, value) {
      if (_sensitiveKeys.contains(key.toLowerCase())) {
        return MapEntry(key, '[redacted]');
      }
      return MapEntry(key, value);
    });
  }

  /// Local-only debug log (never persisted).
  static void debug(String message, {Map<String, dynamic>? data}) {
    if (!kDebugMode) return;
    final suffix = data == null ? '' : ' ${_redact(data)}';
    debugPrint('[QuickServe] $message$suffix');
  }

  /// Persist a business event to `audit_logs`.
  ///
  /// Failures to log are swallowed (and only debug-printed) so logging can
  /// never break the user flow.
  static Future<void> event(
    String eventType, {
    String? entityType,
    String? entityId,
    Map<String, dynamic>? data,
  }) async {
    debug('event:$eventType', data: data);
    if (!persistedEvents.contains(eventType)) return;

    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) return;

    try {
      await client.rpc(
        'log_event',
        params: {
          'p_event_type': eventType,
          'p_entity_type': entityType,
          'p_entity_id': entityId,
          'p_metadata': _redact(data),
        },
      );
    } catch (e) {
      debug('failed to persist event $eventType', data: {'error': e.toString()});
    }
  }
}
