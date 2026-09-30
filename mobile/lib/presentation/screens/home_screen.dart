import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/enums.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import 'request_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final role = ref.watch(userRoleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('QuickServe'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () =>
                showInfoSnack(context, 'No new notifications'),
          ),
        ],
      ),
      floatingActionButton: role == UserRole.customer || role == UserRole.admin
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/requests/new'),
              icon: const Icon(Icons.add),
              label: const Text('New request'),
            )
          : null,
      body: profileAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'Could not load your profile.',
          onRetry: () => ref.invalidate(profileProvider),
        ),
        data: (profile) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(profileProvider);
            ref.invalidate(requestsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _Greeting(profileName: profile?.fullName ?? 'there'),
              const SizedBox(height: 16),
              if (role == UserRole.agent)
                const _AgentSummary()
              else
                const _CustomerSummary(),
              const SizedBox(height: 24),
              _SectionHeader(
                title: role == UserRole.agent ? 'Recently assigned' : 'Recent requests',
                onSeeAll: () => context.go('/requests'),
              ),
              const SizedBox(height: 8),
              const _RecentRequests(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.profileName});

  final String profileName;

  @override
  Widget build(BuildContext context) {
    final now = DateFormat('EEEE, d MMM').format(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hi $profileName 👋',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                )),
        const SizedBox(height: 4),
        Text(now, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _CustomerSummary extends ConsumerWidget {
  const _CustomerSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(requestSummaryProvider);
    return Row(
      children: [
        _StatCard(label: 'Total', value: summary.total, icon: Icons.receipt_long),
        const SizedBox(width: 12),
        _StatCard(
            label: 'Active',
            value: summary.active,
            icon: Icons.timelapse,
            color: const Color(0xFFD97706)),
        const SizedBox(width: 12),
        _StatCard(
            label: 'Completed',
            value: summary.completed,
            icon: Icons.check_circle_outline,
            color: const Color(0xFF059669)),
      ],
    );
  }
}

class _AgentSummary extends ConsumerWidget {
  const _AgentSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(requestsProvider).value ?? const [];
    final active = requests
        .where((r) =>
            r.status == RequestStatus.assigned ||
            r.status == RequestStatus.accepted ||
            r.status == RequestStatus.inProgress)
        .length;
    final done = requests
        .where((r) => r.status == RequestStatus.completed)
        .length;
    return Row(
      children: [
        _StatCard(
            label: 'To do', value: active, icon: Icons.work_outline,
            color: const Color(0xFF2563EB)),
        const SizedBox(width: 12),
        _StatCard(
            label: 'Completed', value: done, icon: Icons.check_circle_outline,
            color: const Color(0xFF059669)),
        const SizedBox(width: 12),
        _StatCard(label: 'Total', value: requests.length, icon: Icons.list_alt),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: c, size: 22),
              const SizedBox(height: 10),
              Text('$value',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        if (onSeeAll != null)
          TextButton(onPressed: onSeeAll, child: const Text('See all')),
      ],
    );
  }
}

class _RecentRequests extends ConsumerWidget {
  const _RecentRequests();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(requestsProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: LoadingView(),
      ),
      error: (e, _) => ErrorView(
        message: 'Could not load requests.',
        onRetry: () => ref.invalidate(requestsProvider),
      ),
      data: (requests) {
        if (requests.isEmpty) {
          return const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'No requests yet',
            subtitle: 'Tap "New request" to book a service.',
          );
        }
        final recent = requests.take(3).toList();
        return Column(
          children: [
            for (final r in recent) ...[
              RequestCard(request: r),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}
