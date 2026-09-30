import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../domain/validators.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';

class RequestDetailsScreen extends ConsumerStatefulWidget {
  const RequestDetailsScreen({super.key, required this.requestId});

  final String requestId;

  @override
  ConsumerState<RequestDetailsScreen> createState() =>
      _RequestDetailsScreenState();
}

class _RequestDetailsScreenState extends ConsumerState<RequestDetailsScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action,
      {String? successMessage}) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(requestDetailProvider(widget.requestId));
      ref.invalidate(requestHistoryProvider(widget.requestId));
      ref.invalidate(requestsProvider);
      if (mounted && successMessage != null) {
        showInfoSnack(context, successMessage);
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, ErrorMapper.map(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advanceStatus(RequestStatus to, {String? label}) async {
    await _run(
      () => ref.read(requestRepositoryProvider).updateStatus(
            requestId: widget.requestId,
            to: to,
          ),
      successMessage: label ?? 'Updated to ${to.label}',
    );
  }

  Future<void> _cancel() async {
    final reason = await _prompt(
      title: 'Cancel request',
      hint: 'Reason (optional)',
      confirmLabel: 'Cancel request',
    );
    if (reason == null) return;
    await _run(
      () => ref.read(requestRepositoryProvider).cancel(
            requestId: widget.requestId,
            reason: reason.isEmpty ? null : reason,
          ),
      successMessage: 'Request cancelled',
    );
  }

  /// Returns entered text, `''` for empty-allowed, or null when dismissed.
  Future<String?> _prompt({
    required String title,
    required String hint,
    required String confirmLabel,
    bool required = false,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (required && text.isEmpty) return;
              Navigator.of(ctx).pop(text);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(requestDetailProvider(widget.requestId));
    final role = ref.watch(userRoleProvider);
    final userId = ref.watch(supabaseProvider).auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Request details')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: ErrorMapper.map(e).message,
          onRetry: () =>
              ref.invalidate(requestDetailProvider(widget.requestId)),
        ),
        data: (request) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(requestDetailProvider(widget.requestId));
            ref.invalidate(requestHistoryProvider(widget.requestId));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _HeaderCard(request: request),
              const SizedBox(height: 16),
              _Actions(
                request: request,
                role: role,
                isOwner: request.customerId == userId,
                busy: _busy,
                onAdvance: _advanceStatus,
                onCancel: _cancel,
                onNote: _addNoteFlow,
              ),
              const SizedBox(height: 16),
              _DetailsCard(request: request),
              const SizedBox(height: 16),
              _Timeline(requestId: widget.requestId),
            ],
          ),
        ),
      ),
    );
  }

  void _addNoteFlow() async {
    final note = await _prompt(
      title: 'Add note',
      hint: 'Note',
      confirmLabel: 'Save note',
    );
    if (note == null || note.trim().isEmpty) return;
    await _run(
      () => ref.read(requestRepositoryProvider).addNote(
            requestId: widget.requestId,
            note: note,
          ),
      successMessage: 'Note added',
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.serviceName ?? 'Service',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusChip(status: request.status),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                SelectableText(
                  request.requestId,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 12),
                PriorityChip(priority: request.priority),
              ],
            ),
            if (request.status == RequestStatus.cancelled &&
                (request.cancelReason?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Cancelled: ${request.cancelReason}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.request,
    required this.role,
    required this.isOwner,
    required this.busy,
    required this.onAdvance,
    required this.onCancel,
    required this.onNote,
  });

  final ServiceRequest request;
  final UserRole role;
  final bool isOwner;
  final bool busy;
  final Future<void> Function(RequestStatus to, {String? label}) onAdvance;
  final Future<void> Function() onCancel;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) {
    final status = request.status;
    final buttons = <Widget>[];

    final next = StatusRules.agentNext(status);
    // RLS only shows an agent their own assignments, so a non-null agent
    // on a visible row is the signed-in agent.
    final isAssignedAgent = role == UserRole.agent && request.agentId != null;

    if (next != null && (role == UserRole.admin || isAssignedAgent)) {
      final label = role == UserRole.admin
          ? 'Move to ${next.label}'
          : switch (next) {
              RequestStatus.accepted => 'Accept request',
              RequestStatus.inProgress => 'Start work',
              RequestStatus.completed => 'Mark completed',
              _ => 'Update status',
            };
      buttons.add(FilledButton(
        onPressed: busy ? null : () => onAdvance(next, label: label),
        child: Text(label),
      ));
    }

    final canCancel = role == UserRole.admin
        ? status.isActive
        : role == UserRole.customer &&
            isOwner &&
            StatusRules.customerCanCancel(status);

    if (canCancel) {
      buttons.add(FilledButton(
        onPressed: busy ? null : onCancel,
        child: const Text('Cancel request'),
      ));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Actions', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            if (buttons.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'No actions available for this status.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              ...buttons.map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: b,
                  )),
            OutlinedButton.icon(
              onPressed: busy ? null : onNote,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Add note'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Details', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            _row(context, Icons.description_outlined, 'Description',
                request.description),
            _row(context, Icons.event_outlined, 'Preferred',
                DateFormat('EEE, d MMM yyyy • h:mm a')
                    .format(request.preferredAt.toLocal())),
            _row(context, Icons.location_on_outlined, 'Address',
                request.address),
            if (request.customerName != null)
              _row(context, Icons.person_outline, 'Customer',
                  request.customerName!),
            _row(
                context,
                Icons.engineering_outlined,
                'Agent',
                request.agentName ?? 'Not assigned yet'),
            _row(
                context,
                Icons.schedule,
                'Created',
                DateFormat('d MMM yyyy, h:mm a')
                    .format(request.createdAt.toLocal())),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    )),
          ),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(requestHistoryProvider(requestId));
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status history', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(12),
                child: LoadingView(),
              ),
              error: (e, _) => Text('Could not load history.',
                  style: theme.textTheme.bodySmall),
              data: (entries) {
                if (entries.isEmpty) {
                  return Text('No history yet.',
                      style: theme.textTheme.bodySmall);
                }
                return Column(
                  children: [
                    for (var i = entries.length - 1; i >= 0; i--)
                      _Tile(entry: entries[i], isLast: i == 0),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.entry, required this.isLast});

  final StatusHistoryEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = entry.toStatus == entry.fromStatus
        ? theme.colorScheme.outline
        : statusColor(context, entry.toStatus.raw);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.toStatus == entry.fromStatus
                        ? 'Note added'
                        : (entry.fromStatus == null
                            ? entry.toStatus.label
                            : '${entry.fromStatus!.label} → ${entry.toStatus.label}'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (entry.note != null && entry.note!.isNotEmpty)
                    Text(entry.note!, style: theme.textTheme.bodySmall),
                  Text(
                    '${entry.changedByName ?? 'System'} • ${DateFormat('d MMM, h:mm a').format(entry.createdAt.toLocal())}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
