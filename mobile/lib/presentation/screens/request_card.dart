import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class RequestCard extends StatelessWidget {
  const RequestCard({super.key, required this.request, this.trailing});

  final ServiceRequest request;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/requests/${request.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      request.serviceName ?? 'Service',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatusChip(status: request.status, compact: true),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                request.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.confirmation_number_outlined,
                      size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(request.requestId,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  Icon(Icons.schedule, size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('d MMM, h:mm a').format(request.preferredAt.toLocal()),
                    style: theme.textTheme.labelSmall,
                  ),
                  const Spacer(),
                  _PriorityDot(priority: request.priority),
                ],
              ),
              if (trailing != null) ...[const Divider(height: 16), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class _PriorityDot extends StatelessWidget {
  const _PriorityDot({required this.priority});

  final RequestPriority priority;

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(context, priority.raw);
    return Tooltip(
      message: '${priority.label} priority',
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
