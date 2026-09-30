import 'enums.dart';

/// Mirrors `public.profiles`.
class Profile {
  const Profile({
    required this.id,
    required this.email,
    required this.fullName,
    this.phone,
    required this.role,
    this.createdAt,
  });

  final String id;
  final String email;
  final String fullName;
  final String? phone;
  final UserRole role;
  final DateTime? createdAt;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        email: (json['email'] as String?) ?? '',
        fullName: (json['full_name'] as String?) ?? '',
        phone: json['phone'] as String?,
        role: UserRole.fromRaw(json['role'] as String?),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse(json['created_at'] as String),
      );
}

/// Mirrors `public.services`.
class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.name,
    required this.description,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String description;
  final bool isActive;

  factory ServiceItem.fromJson(Map<String, dynamic> json) => ServiceItem(
        id: json['id'] as String,
        name: json['name'] as String,
        description: (json['description'] as String?) ?? '',
        isActive: (json['is_active'] as bool?) ?? true,
      );
}

/// Mirrors `public.service_requests`.
class ServiceRequest {
  const ServiceRequest({
    required this.id,
    required this.requestId,
    required this.customerId,
    this.agentId,
    required this.serviceId,
    required this.description,
    required this.preferredAt,
    required this.address,
    required this.priority,
    required this.status,
    this.cancelReason,
    required this.createdAt,
    required this.updatedAt,
    this.serviceName,
    this.customerName,
    this.agentName,
  });

  final String id;
  final String requestId;
  final String customerId;
  final String? agentId;
  final String serviceId;
  final String description;
  final DateTime preferredAt;
  final String address;
  final RequestPriority priority;
  final RequestStatus status;
  final String? cancelReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Denormalised names (joined by the repository when available).
  final String? serviceName;
  final String? customerName;
  final String? agentName;

  ServiceRequest copyWith({RequestStatus? status, String? agentId}) => ServiceRequest(
        id: id,
        requestId: requestId,
        customerId: customerId,
        agentId: agentId ?? this.agentId,
        serviceId: serviceId,
        description: description,
        preferredAt: preferredAt,
        address: address,
        priority: priority,
        status: status ?? this.status,
        cancelReason: cancelReason,
        createdAt: createdAt,
        updatedAt: updatedAt,
        serviceName: serviceName,
        customerName: customerName,
        agentName: agentName,
      );

  factory ServiceRequest.fromJson(Map<String, dynamic> json) {
    final services = json['services'];
    final customer = json['customer'];
    final agent = json['agent'];
    return ServiceRequest(
      id: json['id'] as String,
      requestId: (json['request_id'] as String?) ?? '',
      customerId: json['customer_id'] as String,
      agentId: json['agent_id'] as String?,
      serviceId: json['service_id'] as String,
      description: (json['description'] as String?) ?? '',
      preferredAt: DateTime.parse(json['preferred_at'] as String),
      address: (json['address'] as String?) ?? '',
      priority: RequestPriority.fromRaw(json['priority'] as String?),
      status: RequestStatus.fromRaw(json['status'] as String?),
      cancelReason: json['cancel_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      serviceName: services is Map ? services['name'] as String? : null,
      customerName: customer is Map ? customer['full_name'] as String? : null,
      agentName: agent is Map ? agent['full_name'] as String? : null,
    );
  }
}

/// Mirrors `public.request_status_history`.
class StatusHistoryEntry {
  const StatusHistoryEntry({
    required this.fromStatus,
    required this.toStatus,
    this.note,
    this.changedByName,
    required this.createdAt,
  });

  final RequestStatus? fromStatus;
  final RequestStatus toStatus;
  final String? note;
  final String? changedByName;
  final DateTime createdAt;

  factory StatusHistoryEntry.fromJson(Map<String, dynamic> json) {
    final changedBy = json['changed_by_user'];
    return StatusHistoryEntry(
      fromStatus: json['from_status'] == null
          ? null
          : RequestStatus.fromRaw(json['from_status'] as String),
      toStatus: RequestStatus.fromRaw(json['to_status'] as String),
      note: json['note'] as String?,
      changedByName: changedBy is Map ? changedBy['full_name'] as String? : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
