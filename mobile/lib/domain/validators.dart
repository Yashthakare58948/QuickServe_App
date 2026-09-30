import 'enums.dart';

/// Pure, unit-testable form validation rules.
class Validators {
  Validators._();

  static final _email = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');
  static final _requestId = RegExp(r'^REQ-\d{4}-\d{6}$');
  static final _phone = RegExp(r'^[6-9]\d{9}$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!_email.hasMatch(v)) return 'Enter a valid email';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if ((value ?? '').isEmpty) return 'Please confirm your password';
    if (value != password) return 'Passwords do not match';
    return null;
  }

  static String? required(String? value, {String field = 'This field'}) {
    if ((value?.trim() ?? '').isEmpty) return '$field is required';
    return null;
  }

  static String? description(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Description is required';
    if (v.length < 10) return 'Describe the issue in at least 10 characters';
    if (v.length > 2000) return 'Description is too long';
    return null;
  }

  static String? address(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Address is required';
    if (v.length < 5) return 'Enter a complete address';
    if (v.length > 500) return 'Address is too long';
    return null;
  }

  static String? phone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null; // optional
    if (!_phone.hasMatch(v)) return 'Enter a valid 10-digit phone number';
    return null;
  }

  static String? fullName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Name is required';
    if (v.length < 2) return 'Enter your full name';
    return null;
  }

  static bool isRequestId(String value) => _requestId.hasMatch(value.trim());
}

/// Pure mirror of the database transition table, used for enabling/disabling
/// UI actions. The database remains the source of truth.
class StatusRules {
  StatusRules._();

  static const _transitions = <RequestStatus, Set<RequestStatus>>{
    RequestStatus.created: {RequestStatus.assigned, RequestStatus.cancelled},
    RequestStatus.assigned: {RequestStatus.accepted, RequestStatus.cancelled},
    RequestStatus.accepted: {RequestStatus.inProgress, RequestStatus.cancelled},
    RequestStatus.inProgress: {RequestStatus.completed, RequestStatus.cancelled},
    RequestStatus.completed: {},
    RequestStatus.cancelled: {},
  };

  static bool isValid(RequestStatus from, RequestStatus to) =>
      _transitions[from]?.contains(to) ?? false;

  /// Next action an agent may take from [status].
  static RequestStatus? agentNext(RequestStatus status) => switch (status) {
        RequestStatus.assigned => RequestStatus.accepted,
        RequestStatus.accepted => RequestStatus.inProgress,
        RequestStatus.inProgress => RequestStatus.completed,
        _ => null,
      };

  /// Whether a customer may cancel their request from [status].
  static bool customerCanCancel(RequestStatus status) =>
      status == RequestStatus.created || status == RequestStatus.assigned;
}

/// Formats/parses the human facing id `REQ-2026-000123`.
class RequestId {
  RequestId._();

  static String format(int sequence, {int? year}) {
    final y = year ?? DateTime.now().year;
    final seq = sequence.toString().padLeft(6, '0');
    return 'REQ-$y-$seq';
  }

  static bool isValid(String value) => Validators.isRequestId(value);
}
