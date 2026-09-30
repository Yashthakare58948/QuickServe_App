import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/enums.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import 'request_card.dart';

/// "My Requests" (customer/admin) or "History" (agent).
/// RLS decides which rows are visible to the signed-in user.
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  RequestStatus? _filter;
  String _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(userRoleProvider);
    final async = ref.watch(requestsProvider);
    final canCreate = canCreateRequest(role);

    return Scaffold(
      appBar: AppBar(
        title: Text(role == UserRole.agent ? 'My work' : 'My Requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(requestsProvider),
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () => context.go('/requests/new'),
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search by ID, service or address',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                for (final s in const [
                  RequestStatus.created,
                  RequestStatus.assigned,
                  RequestStatus.accepted,
                  RequestStatus.inProgress,
                  RequestStatus.completed,
                  RequestStatus.cancelled,
                ])
                  _FilterChip(
                    label: s.label,
                    selected: _filter == s,
                    onSelected: (_) => setState(() => _filter = s),
                  ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const LoadingView(label: 'Loading requests…'),
              error: (e, _) => ErrorView(
                message: 'Could not load your requests.',
                onRetry: () => ref.invalidate(requestsProvider),
              ),
              data: (requests) {
                final filtered = requests.where((r) {
                  final matchesStatus = _filter == null || r.status == _filter;
                  final matchesQuery = _query.isEmpty ||
                      r.requestId.toLowerCase().contains(_query) ||
                      r.address.toLowerCase().contains(_query) ||
                      (r.serviceName ?? '').toLowerCase().contains(_query) ||
                      r.description.toLowerCase().contains(_query);
                  return matchesStatus && matchesQuery;
                }).toList();

                if (filtered.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(requestsProvider),
                    child: EmptyState(
                      icon: Icons.inbox_outlined,
                      title: requests.isEmpty ? 'No requests yet' : 'No matches',
                      subtitle: requests.isEmpty
                          ? 'Create your first service request.'
                          : 'Try a different filter or search term.',
                      action: requests.isEmpty && canCreate
                          ? FilledButton(
                              onPressed: () => context.go('/requests/new'),
                              child: const Text('New request'),
                            )
                          : null,
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(requestsProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => RequestCard(request: filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: onSelected,
      ),
    );
  }
}
