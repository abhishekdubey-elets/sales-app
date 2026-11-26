import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_back_button.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/paginated_list_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/followup_models.dart';
import '../data/followups_repository.dart';

class FollowupsScreen extends ConsumerStatefulWidget {
  const FollowupsScreen({super.key});

  @override
  ConsumerState<FollowupsScreen> createState() => _FollowupsScreenState();
}

class _FollowupsScreenState extends ConsumerState<FollowupsScreen> with SingleTickerProviderStateMixin {
  static const _tabs = [
    ('Overdue', 'pending', 'overdue'),
    ('Today', 'pending', 'today'),
    ('Upcoming', 'pending', 'upcoming'),
    ('Done', 'done', null),
  ];
  late final _controller = TabController(length: _tabs.length, vsync: this);
  final _lists = List.generate(_tabs.length, (_) => PaginatedListController());

  @override
  void dispose() {
    _controller.dispose();
    for (final l in _lists) {
      l.dispose();
    }
    super.dispose();
  }

  void _refreshAll() {
    for (final l in _lists) {
      l.refresh();
    }
    ref.invalidate(dueFollowupsProvider);
  }

  Future<void> _markDone(Followup f) async {
    try {
      await ref.read(followupsRepositoryProvider).update(f.id, status: FollowupStatus.done.value);
      if (mounted) showSnack(context, 'Marked as done');
      _refreshAll();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _reschedule(Followup f) async {
    final now = DateTime.now();
    final base = f.dueAt?.toLocal() ?? now;
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: base.isBefore(now) ? now : base,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (time == null) return;
    try {
      await ref
          .read(followupsRepositoryProvider)
          .update(f.id, dueAt: DateTime(date.year, date.month, date.day, time.hour, time.minute));
      if (mounted) showSnack(context, 'Follow-up rescheduled');
      _refreshAll();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Follow-ups'),
        bottom: TabBar(
          controller: _controller,
          tabs: [for (final t in _tabs) Tab(text: t.$1)],
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            ContentConstraint(
              child: PaginatedListView<Followup>(
                controller: _lists[i],
                fetch: (page) =>
                    ref.read(followupsRepositoryProvider).list(status: _tabs[i].$2, due: _tabs[i].$3, page: page),
                empty: EmptyState(
                  title: i == 0 ? 'Nothing overdue' : 'No follow-ups',
                  icon: Icons.event_available_outlined,
                ),
                itemBuilder: (context, f, _) => _FollowupTile(
                  followup: f,
                  onDone: f.status == FollowupStatus.pending ? () => _markDone(f) : null,
                  onReschedule: f.status == FollowupStatus.pending ? () => _reschedule(f) : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FollowupTile extends StatelessWidget {
  const _FollowupTile({required this.followup, this.onDone, this.onReschedule});

  final Followup followup;
  final VoidCallback? onDone;
  final VoidCallback? onReschedule;

  @override
  Widget build(BuildContext context) {
    final f = followup;
    return ListTile(
      onTap: f.leadId == null ? null : () => context.go('/leads/${f.leadId}'),
      leading: AppAvatar(name: f.leadName ?? '?'),
      title: Row(
        children: [
          Flexible(child: Text(f.leadName ?? 'Lead', overflow: TextOverflow.ellipsis)),
          if (f.fromAi) ...[
            const SizedBox(width: 6),
            const StatusChip(label: 'AI', color: AppColors.ai, icon: Icons.smart_toy_outlined, dense: true),
          ],
        ],
      ),
      subtitle: Text(
        [
          formatDateTime(f.dueAt),
          if (f.note != null) f.note!,
          if (f.assignedToName != null) f.assignedToName!,
        ].join(' · '),
      ),
      trailing: onDone == null
          ? StatusChip.followup(f.status, dense: true)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(tooltip: 'Reschedule', onPressed: onReschedule, icon: const Icon(Icons.schedule)),
                IconButton(
                  tooltip: 'Mark done',
                  onPressed: onDone,
                  icon: const Icon(Icons.check_circle_outline, color: AppColors.success),
                ),
              ],
            ),
    );
  }
}
