import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/realtime_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/date_range_filter_bar.dart';
import '../../../core/widgets/paginated_list_view.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/models/date_range_filter.dart';
import '../../auth/providers/auth_controller.dart';
import '../../campaigns/presentation/campaigns_list.dart';
import '../../followups/data/followup_models.dart';
import '../../followups/data/followups_repository.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../data/ai_models.dart';
import '../data/ai_repository.dart';
import 'ai_widgets.dart';

/// AI Voice Agents — separate from human calling: its own dashboard, agents,
/// campaigns and call log. Executives get a read-only view of AI follow-ups routed to them.
class AiHomeScreen extends ConsumerWidget {
  const AiHomeScreen({super.key, this.initialTab});

  final String? initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    if (user.role == UserRole.executive) return const _ExecutiveAiView();
    return _AiManagementView(isAdmin: user.role.isAdmin, initialTab: initialTab);
  }
}

class _AiManagementView extends StatefulWidget {
  const _AiManagementView({required this.isAdmin, this.initialTab});

  final bool isAdmin;
  final String? initialTab;

  @override
  State<_AiManagementView> createState() => _AiManagementViewState();
}

class _AiManagementViewState extends State<_AiManagementView> with SingleTickerProviderStateMixin {
  static const _tabNames = ['overview', 'agents', 'campaigns', 'calls'];
  late final _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: _tabNames.indexOf(widget.initialTab ?? '').clamp(0, 3),
  );

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant _AiManagementView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final i = _tabNames.indexOf(widget.initialTab ?? '');
    if (widget.initialTab != oldWidget.initialTab && i >= 0) _tabs.animateTo(i);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Widget? _fab() {
    if (!widget.isAdmin) return null;
    return switch (_tabs.index) {
      1 => FloatingActionButton.extended(
        onPressed: () => context.go('/ai/agents/new'),
        icon: const Icon(Icons.add),
        label: const Text('New agent'),
      ),
      2 => FloatingActionButton.extended(
        onPressed: () => context.go('/ai/campaigns/new'),
        icon: const Icon(Icons.add),
        label: const Text('New campaign'),
      ),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Voice Agents'),
        actions: const [NotificationBell(), SizedBox(width: 8)],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Agents'),
            Tab(text: 'Campaigns'),
            Tab(text: 'AI calls'),
          ],
        ),
      ),
      floatingActionButton: _fab(),
      body: TabBarView(
        controller: _tabs,
        children: [
          const _OverviewTab(),
          _AgentsTab(isAdmin: widget.isAdmin),
          ContentConstraint(child: CampaignsList(canCreate: widget.isAdmin)),
          const _AiCallsTab(),
        ],
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      final t = next.value?.type;
      if (t == RealtimeEvent.aiCallStatus || t == RealtimeEvent.campaignProgress) ref.invalidate(aiDashboardProvider);
    });
    final range = ref.watch(aiRangeProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(aiDashboardProvider);
        ref.invalidate(voiceStatusProvider);
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 32),
        children: [
          DateRangeFilterBar(value: range, onChanged: ref.read(aiRangeProvider.notifier).set),
          ContentConstraint(
            maxWidth: 1100,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(title: 'AI calling', subtitle: range.label),
                  AsyncValueView<AIDashboard>(
                    value: ref.watch(aiDashboardProvider),
                    onRetry: () => ref.invalidate(aiDashboardProvider),
                    loading: const SizedBox(height: 260, child: LoadingView()),
                    data: (d) => StatGrid(
                      children: [
                        StatCard(
                          label: 'Total AI calls',
                          value: formatNumber(d.totalCalls),
                          icon: Icons.smart_toy_outlined,
                          color: AppColors.ai,
                        ),
                        StatCard(
                          label: 'Calls in progress',
                          value: formatNumber(d.inProgress),
                          icon: Icons.graphic_eq,
                          color: AppColors.warning,
                        ),
                        StatCard(
                          label: 'Calls completed',
                          value: formatNumber(d.completed),
                          icon: Icons.task_alt,
                          color: AppColors.primary,
                        ),
                        StatCard(
                          label: 'Successful conversations',
                          value: formatNumber(d.successfulConversations),
                          icon: Icons.forum_outlined,
                          color: AppColors.success,
                        ),
                        StatCard(
                          label: 'Leads qualified',
                          value: formatNumber(d.qualified),
                          icon: Icons.verified_outlined,
                          color: AppColors.success,
                        ),
                        StatCard(
                          label: 'Interested leads',
                          value: formatNumber(d.interested),
                          icon: Icons.thumb_up_alt_outlined,
                          color: AppColors.teal,
                        ),
                        StatCard(
                          label: 'Follow-ups required',
                          value: formatNumber(d.followupsRequired),
                          icon: Icons.event_note_outlined,
                          color: AppColors.warning,
                        ),
                        StatCard(
                          label: 'Avg. call duration',
                          value: formatDuration(d.avgDurationSeconds),
                          icon: Icons.timer_outlined,
                        ),
                        StatCard(
                          label: 'Human handoffs',
                          value: formatNumber(d.handoffs),
                          icon: Icons.support_agent,
                          color: AppColors.ai,
                        ),
                      ],
                    ),
                  ),
                  const SectionHeader(title: 'Infrastructure'),
                  AsyncValueView<VoiceStatus>(
                    value: ref.watch(voiceStatusProvider),
                    compactError: true,
                    onRetry: () => ref.invalidate(voiceStatusProvider),
                    loading: const SizedBox(height: 120, child: LoadingView()),
                    data: (s) => VoiceStatusCard(status: s),
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

class _AgentsTab extends ConsumerWidget {
  const _AgentsTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(aiAgentsProvider),
      child: AsyncValueView<List<AIAgent>>(
        value: ref.watch(aiAgentsProvider),
        onRetry: () => ref.invalidate(aiAgentsProvider),
        loading: const SkeletonList(),
        data: (agents) {
          if (agents.isEmpty) {
            return ListView(
              children: [
                SizedBox(
                  height: 400,
                  child: EmptyState(
                    icon: Icons.smart_toy_outlined,
                    title: 'No AI agents yet',
                    message: 'Start from an Elets template: Outreach, Lead Qualification or Event Invitation.',
                    action: isAdmin
                        ? FilledButton.icon(
                            onPressed: () => context.go('/ai/agents/new'),
                            icon: const Icon(Icons.add),
                            label: const Text('Create agent'),
                          )
                        : null,
                  ),
                ),
              ],
            );
          }
          return ContentConstraint(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: agents.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _AgentCard(agent: agents[i]),
            ),
          );
        },
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent});

  final AIAgent agent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = agent.config;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/ai/agents/${agent.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.ai.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.smart_toy, color: AppColors.ai),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(c.name, style: theme.textTheme.titleMedium)),
                        StatusChip(
                          label: agent.isActive ? 'Active' : 'Archived',
                          color: agent.isActive ? AppColors.success : AppColors.neutral,
                          dense: true,
                        ),
                      ],
                    ),
                    if (c.description.isNotEmpty)
                      Text(
                        c.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '${c.language.label} · ${agent.totalCalls} calls · ${agent.successfulConversations} successful',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiCallsTab extends ConsumerStatefulWidget {
  const _AiCallsTab();

  @override
  ConsumerState<_AiCallsTab> createState() => _AiCallsTabState();
}

class _AiCallsTabState extends ConsumerState<_AiCallsTab> with AutomaticKeepAliveClientMixin {
  DateRangeFilter _range = const DateRangeFilter.thisMonth();
  InterestLevel? _interest;
  bool _handoffOnly = false;
  bool _activeOnly = false;
  final _list = PaginatedListController();

  @override
  bool get wantKeepAlive => true;

  AiCallQuery get _query => AiCallQuery(
    range: _range,
    interestLevel: _interest?.value,
    handoff: _handoffOnly ? true : null,
    status: _activeOnly ? CallStatus.connected.value : null,
  );

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      if (next.value?.type == RealtimeEvent.aiCallStatus) _list.refresh();
    });
    return ContentConstraint(
      child: Column(
        children: [
          const SizedBox(height: 12),
          DateRangeFilterBar(value: _range, onChanged: (r) => setState(() => _range = r)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final level in InterestLevel.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text('${level.label} interest'),
                      selected: _interest == level,
                      onSelected: (v) => setState(() => _interest = v ? level : null),
                    ),
                  ),
                FilterChip(
                  label: const Text('Handoffs'),
                  avatar: const Icon(Icons.support_agent, size: 16),
                  selected: _handoffOnly,
                  onSelected: (v) => setState(() => _handoffOnly = v),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Live now'),
                  avatar: const Icon(Icons.graphic_eq, size: 16),
                  selected: _activeOnly,
                  onSelected: (v) => setState(() => _activeOnly = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: PaginatedListView<AICall>(
              controller: _list,
              resetKey: _query,
              fetch: (page) => ref.read(aiRepositoryProvider).calls(_query, page: page),
              empty: const EmptyState(title: 'No AI calls in this period', icon: Icons.smart_toy_outlined),
              itemBuilder: (context, call, _) => AiCallTile(call: call),
            ),
          ),
        ],
      ),
    );
  }
}

/// Executives don't manage agents; they see leads the AI handed to them.
class _ExecutiveAiView extends ConsumerWidget {
  const _ExecutiveAiView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followups = ref.watch(_aiFollowupsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('AI Voice Agents'), actions: const [NotificationBell(), SizedBox(width: 8)]),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_aiFollowupsProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ContentConstraint(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: AppColors.ai.withValues(alpha: 0.08),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.smart_toy, color: AppColors.ai, size: 32),
                          SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Elets AI agents call leads on behalf of the team and hand interested prospects to you. '
                              'Handoffs and AI-qualified leads also arrive as notifications.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SectionHeader(title: 'Follow-ups from AI calls', subtitle: 'Pending, assigned to you'),
                  AsyncValueView<List<Followup>>(
                    value: followups,
                    onRetry: () => ref.invalidate(_aiFollowupsProvider),
                    loading: const SizedBox(height: 160, child: LoadingView()),
                    data: (items) => items.isEmpty
                        ? const Card(
                            child: SizedBox(
                              height: 160,
                              child: EmptyState(title: 'No AI handoffs right now', icon: Icons.support_agent),
                            ),
                          )
                        : Card(
                            child: Column(
                              children: [
                                for (final f in items)
                                  ListTile(
                                    leading: AppAvatar(name: f.leadName ?? '?'),
                                    title: Text(f.leadName ?? 'Lead'),
                                    subtitle: Text([formatDateTime(f.dueAt), if (f.note != null) f.note!].join(' · ')),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: f.leadId == null ? null : () => context.go('/leads/${f.leadId}'),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final _aiFollowupsProvider = FutureProvider.autoDispose<List<Followup>>((ref) async {
  final page = await ref.watch(followupsRepositoryProvider).list(status: 'pending', pageSize: 100);
  return page.items.where((f) => f.fromAi).toList();
});
