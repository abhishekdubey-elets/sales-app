import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/app_back_button.dart';
import '../../../core/models/date_range_filter.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/date_range_filter_bar.dart';
import '../../../core/widgets/state_views.dart';
import '../data/analytics_models.dart';
import '../data/analytics_repository.dart';
import 'charts.dart';

/// Reports for managers and admins.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(analyticsHumanVsAiProvider);
    ref.invalidate(analyticsCallsByDateProvider);
    ref.invalidate(analyticsBySalespersonProvider);
    ref.invalidate(analyticsByDepartmentProvider);
    ref.invalidate(analyticsAgentsProvider);
    ref.invalidate(analyticsCampaignsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Analytics'),
        actions: [
          ExportButton(range: range),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(ref),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            DateRangeFilterBar(value: range, onChanged: ref.read(analyticsRangeProvider.notifier).set),
            ContentConstraint(
              maxWidth: 1100,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(title: 'Human vs AI', subtitle: range.label),
                    _card(
                      AsyncValueView<HumanVsAi>(
                        value: ref.watch(analyticsHumanVsAiProvider),
                        compactError: true,
                        onRetry: () => ref.invalidate(analyticsHumanVsAiProvider),
                        loading: const SizedBox(height: 200, child: LoadingView()),
                        data: (d) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            HumanVsAiChart(data: d),
                            const SizedBox(height: 12),
                            _ChannelTable(data: d),
                          ],
                        ),
                      ),
                    ),
                    const SectionHeader(title: 'Calls by date'),
                    _card(
                      AsyncValueView<List<CallsByDatePoint>>(
                        value: ref.watch(analyticsCallsByDateProvider),
                        compactError: true,
                        onRetry: () => ref.invalidate(analyticsCallsByDateProvider),
                        loading: const SizedBox(height: 200, child: LoadingView()),
                        data: (p) => CallsByDateChart(points: p),
                      ),
                    ),
                    const SectionHeader(title: 'Calls by salesperson'),
                    _card(
                      AsyncValueView<List<LeaderboardRow>>(
                        value: ref.watch(analyticsBySalespersonProvider),
                        compactError: true,
                        onRetry: () => ref.invalidate(analyticsBySalespersonProvider),
                        loading: const SizedBox(height: 200, child: LoadingView()),
                        data: (rows) => Column(
                          children: [
                            SalespersonBarChart(rows: rows),
                            const SizedBox(height: 12),
                            LeaderboardTable(rows: rows),
                          ],
                        ),
                      ),
                    ),
                    const SectionHeader(title: 'Calls by department'),
                    _card(
                      AsyncValueView<List<DepartmentRow>>(
                        value: ref.watch(analyticsByDepartmentProvider),
                        compactError: true,
                        onRetry: () => ref.invalidate(analyticsByDepartmentProvider),
                        loading: const SizedBox(height: 120, child: LoadingView()),
                        data: (rows) => rows.isEmpty
                            ? const SizedBox(height: 120, child: EmptyState(title: 'No data'))
                            : Column(
                                children: [
                                  for (final r in rows)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(r.department),
                                      subtitle: Text(
                                        '${r.calls} calls · ${r.connected} connected · ${formatDuration(r.durationSeconds)}',
                                      ),
                                      trailing: Text(
                                        '${r.conversions} conv.',
                                        style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ),
                    const SectionHeader(title: 'AI agent performance'),
                    _card(
                      AsyncValueView<List<AgentPerformance>>(
                        value: ref.watch(analyticsAgentsProvider),
                        compactError: true,
                        onRetry: () => ref.invalidate(analyticsAgentsProvider),
                        loading: const SizedBox(height: 120, child: LoadingView()),
                        data: (rows) => rows.isEmpty
                            ? const SizedBox(
                                height: 120,
                                child: EmptyState(title: 'No AI calls', icon: Icons.smart_toy_outlined),
                              )
                            : Column(
                                children: [
                                  for (final a in rows)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.smart_toy_outlined, color: AppColors.ai),
                                      title: Text(a.agentName),
                                      subtitle: Text(
                                        '${a.calls} calls · ${a.connected} connected · ${a.successful} successful · '
                                        '${a.qualified} qualified · ${a.handoffs} handoffs · avg ${formatDuration(a.avgDurationSeconds)}',
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ),
                    const SectionHeader(title: 'Campaign performance'),
                    _card(
                      AsyncValueView<List<CampaignPerformance>>(
                        value: ref.watch(analyticsCampaignsProvider),
                        compactError: true,
                        onRetry: () => ref.invalidate(analyticsCampaignsProvider),
                        loading: const SizedBox(height: 120, child: LoadingView()),
                        data: (rows) => rows.isEmpty
                            ? const SizedBox(
                                height: 120,
                                child: EmptyState(title: 'No campaigns', icon: Icons.campaign_outlined),
                              )
                            : Column(
                                children: [
                                  for (final c in rows)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(c.name),
                                      subtitle: Text(
                                        '${c.stats.totalLeads} leads · ${c.stats.attempted} attempted · ${c.stats.connected} connected · '
                                        '${c.stats.qualified} qualified · ${c.stats.conversions} conversions',
                                      ),
                                      trailing: Text(c.status),
                                      onTap: () => context.go('/ai/campaigns/${c.campaignId}'),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.fromLTRB(12, 16, 16, 12), child: child),
  );
}

class _ChannelTable extends StatelessWidget {
  const _ChannelTable({required this.data});

  final HumanVsAi data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    TableRow row(String label, String human, String ai, {bool header = false}) {
      final style = header
          ? theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)
          : theme.textTheme.bodyMedium;
      return TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(label, style: style),
          ),
          Text(human, style: style, textAlign: TextAlign.right),
          Text(ai, style: style, textAlign: TextAlign.right),
        ],
      );
    }

    final h = data.human;
    final a = data.ai;
    return Table(
      columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(), 2: FlexColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        row('', 'Human', 'AI', header: true),
        row('Calls', '${h.calls}', '${a.calls}'),
        row(
          'Connected',
          '${h.connected} (${formatPercent(h.connected, h.calls)})',
          '${a.connected} (${formatPercent(a.connected, a.calls)})',
        ),
        row('Avg. duration', formatDuration(h.avgDurationSeconds), formatDuration(a.avgDurationSeconds)),
        row('Interested', '${h.interested}', '${a.interested}'),
        row('Qualified', '${h.qualified}', '${a.qualified}'),
        row('Converted', '${h.converted}', '${a.converted}'),
      ],
    );
  }
}

/// CSV/XLSX export via a short-lived signed link opened in the browser.
class ExportButton extends ConsumerWidget {
  const ExportButton({super.key, required this.range});

  final DateRangeFilter range;

  static const _reports = [
    ('calls', 'Human calls'),
    ('ai_calls', 'AI calls'),
    ('leads', 'Leads'),
    ('leaderboard', 'Leaderboard'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<(String, String)>(
      tooltip: 'Export',
      icon: const Icon(Icons.download_outlined),
      onSelected: (choice) async {
        final (report, format) = choice;
        try {
          final link = await runWithProgress(
            context,
            () => ref.read(analyticsRepositoryProvider).exportLink(report: report, format: format, range: range),
            message: 'Preparing export…',
          );
          final ok = await launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication);
          if (!ok && context.mounted) showSnack(context, 'Couldn\'t open the download link', error: true);
        } catch (e) {
          if (context.mounted) showSnack(context, errorMessage(e), error: true);
        }
      },
      itemBuilder: (_) => [
        for (final (key, label) in _reports) ...[
          PopupMenuItem(value: (key, 'csv'), child: Text('$label · CSV')),
          PopupMenuItem(value: (key, 'xlsx'), child: Text('$label · Excel')),
        ],
      ],
    );
  }
}
