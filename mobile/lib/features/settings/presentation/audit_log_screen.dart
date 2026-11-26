import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_back_button.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/paginated_list_view.dart';
import '../../../core/widgets/state_views.dart';
import '../data/settings_models.dart';
import '../data/settings_repository.dart';

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), title: const Text('Audit log')),
      body: ContentConstraint(
        child: PaginatedListView<AuditLog>(
          fetch: (page) => ref.read(settingsRepositoryProvider).auditLogs(page: page),
          empty: const EmptyState(title: 'No audit entries', icon: Icons.policy_outlined),
          itemBuilder: (context, log, _) => ListTile(
            leading: AppAvatar(name: log.actorName ?? 'System', radius: 18),
            title: Text(log.action),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    log.actorName ?? 'System',
                    if (log.entityType != null)
                      '${log.entityType}${log.entityId != null ? ' ${log.entityId!.substring(0, log.entityId!.length.clamp(0, 8))}' : ''}',
                    formatDateTime(log.createdAt),
                  ].join(' · '),
                ),
                if (log.details != null)
                  Text(log.details!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ],
            ),
            trailing: log.ipAddress == null ? null : Text(log.ipAddress!, style: theme.textTheme.labelSmall),
          ),
        ),
      ),
    );
  }
}
