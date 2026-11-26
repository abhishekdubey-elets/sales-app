import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/date_range_filter.dart';
import '../../../core/models/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/date_range_filter_bar.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../analytics/data/analytics_models.dart';
import '../../analytics/data/analytics_repository.dart';
import '../../analytics/presentation/charts.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/providers/auth_controller.dart';
import '../../followups/data/followup_models.dart';
import '../../followups/data/followups_repository.dart';
import '../../notifications/presentation/notification_bell.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(dashboardStatsProvider);
    ref.invalidate(dashboardLeaderboardProvider);
    ref.invalidate(dashboardCallsByDateProvider);
    ref.invalidate(dashboardHumanVsAiProvider);
    ref.invalidate(myStatsProvider);
    ref.invalidate(dueFollowupsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final range = ref.watch(dashboardRangeProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${greetingFor(DateTime.now())}, ${user.firstName}', style: theme.textTheme.titleLarge),
            Text(
              '${user.role.label}${user.teamName != null ? ' · ${user.teamName}' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: const [NotificationBell(), SizedBox(width: 8)],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(ref),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            DateRangeFilterBar(value: range, onChanged: ref.read(dashboardRangeProvider.notifier).set),
            const SizedBox(height: 8),
            ContentConstraint(
              maxWidth: 1100,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (user.role.isManagerOrAdmin) _QuickActions(user: user),
                    _StatsSection(range: range),
                    if (user.role == UserRole.executive) ...[const _MyPerformanceStrip(), const _DueFollowups()],
                    if (user.role.isManagerOrAdmin) ...[
                      SectionHeader(
                        title: user.role.isAdmin ? 'Team leaderboard' : 'My team leaderboard',
                        subtitle: range.label,
                        actionLabel: 'Analytics',
                        onAction: () => context.push('/analytics'),
                      ),
                      const _Leaderboard(),
                    ],
                    if (user.role.isAdmin) ...[
                      const SectionHeader(title: 'Calls over time'),
                      const _CallsByDate(),
                      const SectionHeader(title: 'Human vs AI calling'),
                      const _HumanVsAi(),
                    ],
                    if (user.role == UserRole.manager) const _DueFollowups(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.insights, 'Analytics', '/analytics'),
      (Icons.groups_outlined, 'Team', '/team'),
      (Icons.campaign_outlined, 'Campaigns', '/ai?tab=campaigns'),
      (Icons.history, 'Call history', '/calls'),
      (Icons.event_note_outlined, 'Follow-ups', '/followups'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (icon, label, path) in actions)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  onPressed: () => path.startsWith('/ai') ? context.go(path) : context.push(path),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsSection extends ConsumerWidget {
  const _StatsSection({required this.range});

  final DateRangeFilter range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    return AsyncValueView<DashboardStats>(
      value: stats,
      onRetry: () => ref.invalidate(dashboardStatsProvider),
      loading: const SizedBox(height: 280, child: LoadingView()),
      data: (s) {
        final scopeLabel = switch (s.scope) {
          'organization' => 'Organisation',
          'team' => 'Team',
          _ => 'My activity',
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: scopeLabel, subtitle: range.label),
            StatGrid(
              children: [
                StatCard(
                  label: 'Total leads',
                  value: formatNumber(s.totalLeads),
                  icon: Icons.people_alt_outlined,
                  onTap: () => context.go('/leads'),
                ),
                StatCard(
                  label: 'Total calls',
                  value: formatNumber(s.totalCalls),
                  icon: Icons.call_outlined,
                  onTap: () => context.push('/calls'),
                ),
                StatCard(
                  label: 'Successful calls',
                  value: formatNumber(s.successfulCalls),
                  icon: Icons.thumb_up_alt_outlined,
                  color: AppColors.success,
                  caption: formatPercent(s.successfulCalls, s.connectedCalls) == '—'
                      ? null
                      : '${formatPercent(s.successfulCalls, s.connectedCalls)} of connected',
                ),
                StatCard(
                  label: 'Connected',
                  value: formatNumber(s.connectedCalls),
                  icon: Icons.phone_in_talk_outlined,
                  color: AppColors.teal,
                  caption: formatPercent(s.connectedCalls, s.totalCalls) == '—'
                      ? null
                      : '${formatPercent(s.connectedCalls, s.totalCalls)} connect rate',
                ),
                StatCard(
                  label: 'Not connected',
                  value: formatNumber(s.notConnected),
                  icon: Icons.phone_disabled_outlined,
                  color: AppColors.warning,
                ),
                StatCard(
                  label: 'Missed calls',
                  value: formatNumber(s.missedCalls),
                  icon: Icons.phone_missed_outlined,
                  color: AppColors.danger,
                ),
                StatCard(
                  label: 'Total call duration',
                  value: formatDuration(s.totalDurationSeconds),
                  icon: Icons.timer_outlined,
                ),
                StatCard(
                  label: 'Pending follow-ups',
                  value: formatNumber(s.pendingFollowups),
                  icon: Icons.event_note_outlined,
                  color: AppColors.warning,
                  onTap: () => context.push('/followups'),
                ),
                StatCard(
                  label: 'Leads converted',
                  value: formatNumber(s.leadsConverted),
                  icon: Icons.workspace_premium_outlined,
                  color: AppColors.success,
                ),
                StatCard(
                  label: 'AI agent calls',
                  value: formatNumber(s.aiCalls),
                  icon: Icons.smart_toy_outlined,
                  color: AppColors.ai,
                ),
                StatCard(
                  label: 'AI successful conversations',
                  value: formatNumber(s.aiSuccessfulConversations),
                  icon: Icons.forum_outlined,
                  color: AppColors.ai,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _MyPerformanceStrip extends ConsumerWidget {
  const _MyPerformanceStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(myStatsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: 'My performance', actionLabel: 'Details', onAction: () => context.push('/performance')),
        AsyncValueView<MyStats>(
          value: stats,
          compactError: true,
          onRetry: () => ref.invalidate(myStatsProvider),
          loading: const SizedBox(height: 90, child: LoadingView()),
          data: (s) => Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  _Metric(label: 'Today', value: '${s.callsToday}'),
                  _Metric(label: 'This week', value: '${s.callsThisWeek}'),
                  _Metric(label: 'This month', value: '${s.callsThisMonth}'),
                  _Metric(label: 'Avg. duration', value: formatDuration(s.avgDurationSeconds)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(value, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _DueFollowups extends ConsumerWidget {
  const _DueFollowups();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(dueFollowupsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Follow-ups due',
          subtitle: 'Overdue and today',
          actionLabel: 'View all',
          onAction: () => context.push('/followups'),
        ),
        AsyncValueView<List<Followup>>(
          value: due,
          compactError: true,
          onRetry: () => ref.invalidate(dueFollowupsProvider),
          loading: const SizedBox(height: 90, child: LoadingView()),
          data: (items) => items.isEmpty
              ? const Card(
                  child: SizedBox(
                    height: 120,
                    child: EmptyState(title: 'You\'re all caught up', icon: Icons.check_circle_outline),
                  ),
                )
              : Card(
                  child: Column(
                    children: [
                      for (final f in items.take(6))
                        ListTile(
                          leading: AppAvatar(name: f.leadName ?? '?', radius: 18),
                          title: Text(f.leadName ?? 'Lead'),
                          subtitle: Text(f.note ?? (f.fromAi ? 'Requested by AI agent call' : 'Follow-up')),
                          trailing: Text(
                            formatRelative(f.dueAt),
                            style: TextStyle(
                              color: f.isOverdue ? AppColors.danger : null,
                              fontWeight: f.isOverdue ? FontWeight.w700 : null,
                            ),
                          ),
                          onTap: f.leadId == null ? null : () => context.go('/leads/${f.leadId}'),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _Leaderboard extends ConsumerWidget {
  const _Leaderboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: AsyncValueView<List<LeaderboardRow>>(
          value: ref.watch(dashboardLeaderboardProvider),
          compactError: true,
          onRetry: () => ref.invalidate(dashboardLeaderboardProvider),
          loading: const SizedBox(height: 140, child: LoadingView()),
          data: (rows) => LeaderboardTable(rows: rows, limit: 10),
        ),
      ),
    );
  }
}

class _CallsByDate extends ConsumerWidget {
  const _CallsByDate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
        child: AsyncValueView<List<CallsByDatePoint>>(
          value: ref.watch(dashboardCallsByDateProvider),
          compactError: true,
          onRetry: () => ref.invalidate(dashboardCallsByDateProvider),
          loading: const SizedBox(height: 200, child: LoadingView()),
          data: (points) => CallsByDateChart(points: points),
        ),
      ),
    );
  }
}

class _HumanVsAi extends ConsumerWidget {
  const _HumanVsAi();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
        child: AsyncValueView<HumanVsAi>(
          value: ref.watch(dashboardHumanVsAiProvider),
          compactError: true,
          onRetry: () => ref.invalidate(dashboardHumanVsAiProvider),
          loading: const SizedBox(height: 200, child: LoadingView()),
          data: (d) => HumanVsAiChart(data: d),
        ),
      ),
    );
  }
}
