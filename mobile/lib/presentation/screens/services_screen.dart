import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(servicesProvider);
    final canCreate = canCreateRequest(ref.watch(userRoleProvider));

    return Scaffold(
      appBar: AppBar(title: const Text('Services')),
      body: servicesAsync.when(
        loading: () => const LoadingView(label: 'Loading services…'),
        error: (e, _) => ErrorView(
          message: 'Could not load services.',
          onRetry: () => ref.invalidate(servicesProvider),
        ),
        data: (services) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(servicesProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: services.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final s = services[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            child: Icon(_iconFor(s.name),
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              s.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(s.description,
                          style: Theme.of(context).textTheme.bodyMedium),
                      if (canCreate) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonal(
                            onPressed: () =>
                                context.go('/requests/new?service=${s.id}'),
                            child: const Text('Book this service'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('ac')) return Icons.ac_unit_outlined;
    if (n.contains('plumb')) return Icons.plumbing_outlined;
    if (n.contains('electric')) return Icons.electrical_services_outlined;
    if (n.contains('clean')) return Icons.cleaning_services_outlined;
    return Icons.home_repair_service_outlined;
  }
}
