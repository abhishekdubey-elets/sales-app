import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_back_button.dart';
import '../../../core/models/date_range_filter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/date_range_filter_bar.dart';
import '../../../core/widgets/stat_card.dart';
import '../data/analytics_models.dart';
import '../data/analytics_repository.dart';

/// Personal analytics (`/analytics/me`), available to every role.
class MyPerformanceScreen extends ConsumerWidget {
  const MyPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(myStatsRangeProvider);
    final stats = ref.watch(myStatsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('My performance'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/calls'),
            icon: const Icon(Icons.history),
            label: const Text('My calls'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myStatsProvider),
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            DateRangeFilterBar(value: range, onChanged: ref.read(myStatsRangeProvider.notifier).set),
            ContentConstraint(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AsyncValueView<MyStats>(
                  value: stats,
                  onRetry: () => ref.invalidate(myStatsProvider),
                  data: (s) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader(title: 'Call volume'),
                      StatGrid(
                        children: [
                          StatCard(label: 'My calls today', value: '${s.callsToday}', icon: Icons.today_outlined),
                          StatCard(
                            label: 'My calls this week',
                            value: '${s.callsThisWeek}',
                            icon: Icons.date_range_outlined,
                          ),
                          StatCard(
                            label: 'Total calls this month',
                            value: '${s.callsThisMonth}',
                            icon: Icons.calendar_month_outlined,
                          ),
                        ],
                      ),
                      SectionHeader(title: 'Quality', subtitle: range.label),
                      StatGrid(
                        children: [
                          StatCard(
                            label: 'Connected calls',
                            value: '${s.connected}',
                            icon: Icons.phone_in_talk_outlined,
                            color: AppColors.teal,
                          ),
                          StatCard(
                            label: 'Missed calls',
                            value: '${s.missed}',
                            icon: Icons.phone_missed_outlined,
                            color: AppColors.danger,
                          ),
                          StatCard(
                            label: 'Average call duration',
                            value: formatDuration(s.avgDurationSeconds),
                            icon: Icons.timer_outlined,
                          ),
                          StatCard(
                            label: 'Interested leads',
                            value: '${s.interested}',
                            icon: Icons.thumb_up_alt_outlined,
                            color: AppColors.success,
                          ),
                          StatCard(
                            label: 'Converted leads',
                            value: '${s.converted}',
                            icon: Icons.workspace_premium_outlined,
                            color: AppColors.success,
                          ),
                          StatCard(
                            label: 'Follow-ups pending',
                            value: '${s.followupsPending}',
                            icon: Icons.event_note_outlined,
                            color: AppColors.warning,
                            onTap: () => context.push('/followups'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
