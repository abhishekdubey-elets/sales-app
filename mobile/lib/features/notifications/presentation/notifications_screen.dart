import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_back_button.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/realtime_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/paginated_list_view.dart';
import '../../../core/widgets/state_views.dart';
import '../data/notification_models.dart';
import '../data/notifications_repository.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _unreadOnly = false;
  final _list = PaginatedListController();
  final _locallyRead = <String>{};

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  static (IconData, Color) _style(String type) => switch (NotificationType.fromValue(type)) {
    NotificationType.leadAssigned => (Icons.assignment_ind_outlined, AppColors.primary),
    NotificationType.followupReminder => (Icons.event_note_outlined, AppColors.warning),
    NotificationType.aiQualifiedLead => (Icons.verified_outlined, AppColors.success),
    NotificationType.handoffRequest => (Icons.support_agent, AppColors.ai),
    NotificationType.campaignCompleted => (Icons.flag_outlined, AppColors.teal),
    NotificationType.dailySummary => (Icons.insights, AppColors.primary),
    NotificationType.system => (Icons.info_outline, AppColors.neutral),
  };

  Future<void> _open(AppNotification n) async {
    if (!n.isRead && !_locallyRead.contains(n.id)) {
      setState(() => _locallyRead.add(n.id));
      ref.read(unreadCountProvider.notifier).decrement();
      ref.read(notificationsRepositoryProvider).markRead(n.id).ignore();
    }
    final d = n.data;
    if (!mounted) return;
    if (d['ai_call_id'] != null) {
      context.go('/ai/calls/${d['ai_call_id']}');
    } else if (d['campaign_id'] != null) {
      context.go('/ai/campaigns/${d['campaign_id']}');
    } else if (d['lead_id'] != null) {
      context.go('/leads/${d['lead_id']}');
    } else if (d['call_id'] != null) {
      context.push('/call/${d['call_id']}');
    }
  }

  Future<void> _markAll() async {
    try {
      await ref.read(unreadCountProvider.notifier).markAllRead();
      _list.refresh();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      if (next.value?.type == RealtimeEvent.notification) _list.refresh();
    });
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Notifications'),
        actions: [
          TextButton(onPressed: _markAll, child: const Text('Mark all read')),
          const SizedBox(width: 8),
        ],
      ),
      body: ContentConstraint(
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Unread only'),
              value: _unreadOnly,
              onChanged: (v) => setState(() => _unreadOnly = v),
            ),
            const Divider(),
            Expanded(
              child: PaginatedListView<AppNotification>(
                controller: _list,
                resetKey: _unreadOnly,
                fetch: (page) => ref.read(notificationsRepositoryProvider).list(unreadOnly: _unreadOnly, page: page),
                empty: const EmptyState(title: 'No notifications', icon: Icons.notifications_none),
                itemBuilder: (context, n, _) {
                  final (icon, color) = _style(n.type);
                  final unread = !n.isRead && !_locallyRead.contains(n.id);
                  return ListTile(
                    onTap: () => _open(n),
                    tileColor: unread ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.12),
                      foregroundColor: color,
                      child: Icon(icon, size: 20),
                    ),
                    title: Text(n.title, style: unread ? const TextStyle(fontWeight: FontWeight.w700) : null),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (n.body != null) Text(n.body!),
                        Text(formatRelative(n.createdAt), style: theme.textTheme.labelSmall),
                      ],
                    ),
                    trailing: unread ? const Icon(Icons.circle, size: 10, color: AppColors.primary) : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
