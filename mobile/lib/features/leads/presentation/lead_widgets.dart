import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/status_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/data/auth_models.dart';
import '../../team/data/team_repository.dart';
import '../data/lead_models.dart';

class LeadTile extends StatelessWidget {
  const LeadTile({
    super.key,
    required this.lead,
    this.onTap,
    this.onLongPress,
    this.onCall,
    this.selected = false,
    this.selectionMode = false,
  });

  final Lead lead;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onCall;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final meta = <String>[
      if (lead.nextFollowupAt != null) 'Follow-up ${formatRelative(lead.nextFollowupAt)}',
      if (lead.nextFollowupAt == null && lead.lastCalledAt != null) 'Called ${formatRelative(lead.lastCalledAt)}',
      if (lead.assignedToName != null) lead.assignedToName!,
    ];
    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: selectionMode
          ? Checkbox(value: selected, onChanged: (_) => onTap?.call())
          : Stack(
              clipBehavior: Clip.none,
              children: [
                AppAvatar(name: lead.fullName),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: priorityColor(lead.priority),
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.colorScheme.surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
      title: Row(
        children: [
          Flexible(child: Text(lead.fullName, overflow: TextOverflow.ellipsis)),
          if (lead.isFavourite) ...[
            const SizedBox(width: 4),
            const Icon(Icons.star, size: 14, color: Color(0xFFE0A100)),
          ],
          if (lead.optedOut) ...[const SizedBox(width: 6), Icon(Icons.block, size: 14, color: theme.colorScheme.error)],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lead.subtitle.isNotEmpty) Text(lead.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(
            children: [
              StatusChip.leadStatus(lead.status, dense: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(meta.join(' · '), style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ],
      ),
      trailing: selectionMode || onCall == null
          ? null
          : IconButton.filledTonal(
              tooltip: lead.optedOut ? 'Opted out' : 'Call ${lead.fullName}',
              onPressed: lead.optedOut ? null : onCall,
              icon: const Icon(Icons.call),
            ),
    );
  }
}

/// Bottom sheet to pick a salesperson. Returns the chosen user or null.
Future<User?> showAssigneePicker(BuildContext context, {String title = 'Assign to'}) {
  return showModalBottomSheet<User>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AssigneeSheet(title: title),
  );
}

class _AssigneeSheet extends ConsumerStatefulWidget {
  const _AssigneeSheet({required this.title});

  final String title;

  @override
  ConsumerState<_AssigneeSheet> createState() => _AssigneeSheetState();
}

class _AssigneeSheetState extends ConsumerState<_AssigneeSheet> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(assignableUsersProvider);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search salespeople'),
                onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncValueView<List<User>>(
                value: users,
                onRetry: () => ref.invalidate(assignableUsersProvider),
                data: (list) {
                  final filtered = list
                      .where((u) => _filter.isEmpty || u.fullName.toLowerCase().contains(_filter))
                      .toList();
                  if (filtered.isEmpty) return const EmptyState(title: 'No matching salespeople');
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final u = filtered[i];
                      return ListTile(
                        leading: AppAvatar(name: u.fullName, radius: 18),
                        title: Text(u.fullName),
                        subtitle: Text([u.role.label, if (u.teamName != null) u.teamName!].join(' · ')),
                        onTap: () => Navigator.of(context).pop(u),
                      );
                    },
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
