import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/realtime_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/paginated_list_view.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/campaign_models.dart';
import '../data/campaigns_repository.dart';

class CampaignDetailScreen extends ConsumerStatefulWidget {
  const CampaignDetailScreen({super.key, required this.campaignId});

  final String campaignId;

  @override
  ConsumerState<CampaignDetailScreen> createState() => _CampaignDetailScreenState();
}

class _CampaignDetailScreenState extends ConsumerState<CampaignDetailScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);
  final _leadsList = PaginatedListController();
  final _logsList = PaginatedListController();
  CampaignLeadStatus? _leadStatus;
  bool _busy = false;

  @override
  void dispose() {
    _tabs.dispose();
    _leadsList.dispose();
    _logsList.dispose();
    super.dispose();
  }

  Future<void> _control(Campaign c, String action) async {
    final (title, message, destructive) = switch (action) {
      'start' => ('Start campaign?', 'The agent begins calling leads during the scheduled hours.', false),
      'pause' => ('Pause campaign?', 'Calls in progress finish; no new calls are placed until resumed.', false),
      'resume' => ('Resume campaign?', 'Calling continues from where it paused.', false),
      _ => ('Stop campaign?', 'Stopping is final: remaining leads won\'t be called. Calls in progress finish.', true),
    };
    final ok = await showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: action[0].toUpperCase() + action.substring(1),
      destructive: destructive,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(campaignsRepositoryProvider).control(c.id, action);
      ref.invalidate(campaignDetailProvider(c.id));
      ref.invalidate(campaignsProvider);
      _logsList.refresh();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      final e = next.value;
      if (e?.type == RealtimeEvent.campaignProgress && e?.data['campaign_id']?.toString() == widget.campaignId) {
        ref.invalidate(campaignDetailProvider(widget.campaignId));
        _leadsList.refresh();
        _logsList.refresh();
      }
    });
    final campaign = ref.watch(campaignDetailProvider(widget.campaignId));
    final isAdmin = ref.watch(currentUserProvider)?.role.isAdmin ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(campaign.value?.name ?? 'Campaign'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Leads'),
            Tab(text: 'Logs'),
          ],
        ),
      ),
      body: AsyncValueView<Campaign>(
        value: campaign,
        onRetry: () => ref.invalidate(campaignDetailProvider(widget.campaignId)),
        data: (c) => TabBarView(controller: _tabs, children: [_overview(c, isAdmin), _leads(c), _logs(c)]),
      ),
    );
  }

  Widget _overview(Campaign c, bool isAdmin) {
    final theme = Theme.of(context);
    final s = c.stats;
    final controls = <Widget>[
      if (c.status == CampaignStatus.draft)
        FilledButton.icon(
          onPressed: _busy || s.totalLeads == 0 ? null : () => _control(c, 'start'),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        ),
      if (c.status == CampaignStatus.running)
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _control(c, 'pause'),
          icon: const Icon(Icons.pause),
          label: const Text('Pause'),
        ),
      if (c.status == CampaignStatus.paused)
        FilledButton.icon(
          onPressed: _busy ? null : () => _control(c, 'resume'),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Resume'),
        ),
      if (c.status == CampaignStatus.running || c.status == CampaignStatus.paused)
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _control(c, 'stop'),
          icon: const Icon(Icons.stop, color: AppColors.danger),
          label: const Text('Stop'),
        ),
    ];
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(campaignDetailProvider(c.id)),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentConstraint(
            maxWidth: 1000,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(c.name, style: theme.textTheme.titleLarge)),
                            StatusChip.campaign(c.status),
                          ],
                        ),
                        if (c.description != null) Text(c.description!),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: s.progress,
                            minHeight: 8,
                            color: campaignStatusColor(c.status),
                            backgroundColor: theme.colorScheme.surfaceContainerHigh,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${(s.progress * 100).round()}% processed · ${s.pending} pending · ${s.inProgress} in progress',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (isAdmin && controls.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Wrap(spacing: 10, runSpacing: 10, children: controls),
                        ],
                      ],
                    ),
                  ),
                ),
                const SectionHeader(title: 'Results'),
                StatGrid(
                  children: [
                    StatCard(label: 'Leads uploaded', value: '${s.totalLeads}', icon: Icons.people_alt_outlined),
                    StatCard(
                      label: 'Calls attempted',
                      value: '${s.attempted}',
                      icon: Icons.call_made,
                      color: AppColors.primary,
                    ),
                    StatCard(
                      label: 'Connected',
                      value: '${s.connected}',
                      icon: Icons.phone_in_talk_outlined,
                      color: AppColors.teal,
                    ),
                    StatCard(
                      label: 'Not answered',
                      value: '${s.notAnswered}',
                      icon: Icons.phone_missed_outlined,
                      color: AppColors.warning,
                    ),
                    StatCard(
                      label: 'Interested',
                      value: '${s.interested}',
                      icon: Icons.thumb_up_alt_outlined,
                      color: AppColors.success,
                    ),
                    StatCard(
                      label: 'Qualified',
                      value: '${s.qualified}',
                      icon: Icons.verified_outlined,
                      color: AppColors.success,
                    ),
                    StatCard(
                      label: 'Follow-ups',
                      value: '${s.followups}',
                      icon: Icons.event_note_outlined,
                      color: AppColors.warning,
                    ),
                    StatCard(
                      label: 'Conversions',
                      value: '${s.conversions}',
                      icon: Icons.workspace_premium_outlined,
                      color: AppColors.success,
                    ),
                    StatCard(label: 'Handoffs', value: '${s.handoffs}', icon: Icons.support_agent, color: AppColors.ai),
                    StatCard(label: 'Failed', value: '${s.failed}', icon: Icons.error_outline, color: AppColors.danger),
                    StatCard(label: 'Opted out', value: '${s.optedOut}', icon: Icons.block, color: AppColors.danger),
                  ],
                ),
                const SectionHeader(title: 'Configuration'),
                InfoCard(
                  child: Column(
                    children: [
                      KeyValueRow(label: 'Agent', value: c.agentName),
                      KeyValueRow(label: 'Days', value: c.schedule.daysLabel),
                      KeyValueRow(
                        label: 'Hours',
                        value: '${c.schedule.startTime}–${c.schedule.endTime} (${c.schedule.timezone})',
                      ),
                      KeyValueRow(
                        label: 'Dates',
                        value: '${c.schedule.startDate ?? 'Immediately'} → ${c.schedule.endDate ?? 'No end date'}',
                      ),
                      KeyValueRow(
                        label: 'Retries',
                        value: '${c.maxAttempts} attempts, ${c.retryDelayMinutes} min apart',
                      ),
                      KeyValueRow(
                        label: 'Throughput',
                        value: '${c.maxConcurrentCalls} concurrent · ${c.callsPerMinute}/min',
                      ),
                      KeyValueRow(label: 'Created', value: formatDateTime(c.createdAt)),
                      KeyValueRow(label: 'Started', value: formatDateTime(c.startedAt)),
                      KeyValueRow(label: 'Completed', value: formatDateTime(c.completedAt)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _leads(Campaign c) {
    return ContentConstraint(
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _leadStatus == null,
                  onSelected: (_) => setState(() => _leadStatus = null),
                ),
                for (final s in CampaignLeadStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(s.label),
                      selected: _leadStatus == s,
                      onSelected: (_) => setState(() => _leadStatus = s),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PaginatedListView<CampaignLead>(
              controller: _leadsList,
              resetKey: _leadStatus,
              fetch: (page) =>
                  ref.read(campaignsRepositoryProvider).leads(c.id, status: _leadStatus?.value, page: page),
              empty: const EmptyState(title: 'No leads', icon: Icons.people_alt_outlined),
              itemBuilder: (context, l, _) => ListTile(
                onTap: l.lastAiCallId != null
                    ? () => context.go('/ai/calls/${l.lastAiCallId}')
                    : (l.leadId != null ? () => context.go('/leads/${l.leadId}') : null),
                leading: AppAvatar(name: l.leadName ?? '?'),
                title: Text(l.leadName ?? 'Lead'),
                subtitle: Text(
                  [
                    if (l.companyName != null) l.companyName!,
                    '${l.attempts} attempt(s)',
                    if (l.lastCallStatus != null) l.lastCallStatus!.label,
                    if (l.nextAttemptAt != null && l.status == CampaignLeadStatus.pending)
                      'next ${formatRelative(l.nextAttemptAt)}',
                  ].join(' · '),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusChip.campaignLead(l.status, dense: true),
                    if (l.interestLevel != null) ...[
                      const SizedBox(height: 4),
                      StatusChip.interest(l.interestLevel!, dense: true),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logs(Campaign c) {
    return ContentConstraint(
      child: PaginatedListView<CampaignLog>(
        controller: _logsList,
        fetch: (page) => ref.read(campaignsRepositoryProvider).logs(c.id, page: page),
        empty: const EmptyState(title: 'No log entries yet', icon: Icons.receipt_long_outlined),
        itemBuilder: (context, log, _) {
          final color = switch (log.level) {
            'error' => AppColors.danger,
            'warning' => AppColors.warning,
            _ => AppColors.primary,
          };
          return ListTile(
            dense: true,
            leading: Icon(
              log.level == 'error'
                  ? Icons.error_outline
                  : log.level == 'warning'
                  ? Icons.warning_amber_rounded
                  : Icons.info_outline,
              color: color,
            ),
            title: Text(log.message),
            subtitle: Text('${log.event} · ${formatDateTime(log.createdAt)}'),
            onTap: log.aiCallId != null ? () => context.go('/ai/calls/${log.aiCallId}') : null,
          );
        },
      ),
    );
  }
}
