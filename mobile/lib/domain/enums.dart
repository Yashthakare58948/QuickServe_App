/// Domain enums and value parsing shared by the whole app.
library;

enum UserRole {
  customer('customer'),
  agent('agent'),
  admin('admin');

  const UserRole(this.raw);
  final String raw;

  static UserRole fromRaw(String? value) =>
      UserRole.values.firstWhere((r) => r.raw == value, orElse: () => UserRole.customer);
}

enum RequestStatus {
  created('created', 'New'),
  assigned('assigned', 'Assigned'),
  accepted('accepted', 'Accepted'),
  inProgress('in_progress', 'In progress'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const RequestStatus(this.raw, this.label);
  final String raw;
  final String label;

  static RequestStatus fromRaw(String? value) => RequestStatus.values.firstWhere(
        (s) => s.raw == value,
        orElse: () => RequestStatus.created,
      );

  bool get isTerminal => this == completed || this == cancelled;
  bool get isActive => !isTerminal;
}

enum RequestPriority {
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High');

  const RequestPriority(this.raw, this.label);
  final String raw;
  final String label;

  static RequestPriority fromRaw(String? value) => RequestPriority.values.firstWhere(
        (p) => p.raw == value,
        orElse: () => RequestPriority.medium,
      );
}
