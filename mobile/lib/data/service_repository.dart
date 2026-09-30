import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models.dart';

/// Data access for `services`.
class ServiceRepository {
  ServiceRepository(this._client);

  final SupabaseClient _client;

  static const _select = '''
    id, name, description, is_active
  ''';

  Future<List<ServiceItem>> fetchAll() async {
    final rows = await _client
        .from('services')
        .select(_select)
        .eq('is_active', true)
        .order('name');
    return rows.map(ServiceItem.fromJson).toList();
  }
}
