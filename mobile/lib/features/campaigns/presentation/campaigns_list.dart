import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/realtime_service.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/campaign_models.dart';
import '../data/campaigns_repository.dart';

/// Campaign cards with status and progress; refreshes on `campaign.progress` events.
class CampaignsList extends ConsumerWidget {
  const CampaignsList({super.key, this.canCreate = false});

  final bool canCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      if (next.value?.type == RealtimeEvent.campaignProgress) ref.invalidate(campaignsProvider);
    });
    final campaigns = ref.watch(campaignsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(campaignsProvider),
      child: AsyncValueView<List<Campaign>>(
        value: campaigns,
        onRetry: () => ref.invalidate(campaignsProvider),
        loading: const SkeletonList(),
        data: (items) {
          if (items.isEmpty) {
            return ListView(
              children: [
                SizedBox(
                  height: 400,
                  child: EmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'No campaigns yet',
                    message: 'A campaign runs an AI agent over a list of leads within your calling schedule.',
                    action: canCreate
                        ? FilledButton.icon(
                            onPressed: () => context.go('/ai/campaigns/new'),
                            icon: const Icon(Icons.add),
                            label: const Text('Create campaign'),
                          )
                        : null,
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => CampaignCard(campaign: items[i]),
          );
        },
      ),
    );
  }
}

class CampaignCard extends StatelessWidget {
  const CampaignCard({super.key, required this.campaign});

  final Campaign campaign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = campaign.stats;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/ai/campaigns/${campaign.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(campaign.name, style: theme.textTheme.titleMedium)),
                  StatusChip.campaign(campaign.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  campaign.agentName ?? 'Agent',
                  '${campaign.schedule.daysLabel} ${campaign.schedule.startTime}–${campaign.schedule.endTime}',
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: s.progress,
                  minHeight: 6,
                  color: campaignStatusColor(campaign.status),
                  backgroundColor: theme.colorScheme.surfaceContainerHigh,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _Mini(label: 'Leads', value: s.totalLeads),
                  _Mini(label: 'Attempted', value: s.attempted),
                  _Mini(label: 'Connected', value: s.connected),
                  _Mini(label: 'Qualified', value: s.qualified),
                  _Mini(label: 'Interested', value: s.interested),
                ],
              ),
              if (campaign.startedAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Started ${formatRelative(campaign.startedAt)}',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        children: [
          TextSpan(
            text: '$value ',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: label),
        ],
      ),
    );
  }
}
