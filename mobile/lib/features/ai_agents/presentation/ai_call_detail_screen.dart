import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/realtime_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/providers/auth_controller.dart';
import '../../calls/presentation/recording_player.dart';
import '../data/ai_models.dart';
import '../data/ai_repository.dart';
import 'ai_widgets.dart';

class AiCallDetailScreen extends ConsumerWidget {
  const AiCallDetailScreen({super.key, required this.callId});

  final String callId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      final e = next.value;
      if (e?.type == RealtimeEvent.aiCallStatus && e?.data['id']?.toString() == callId) {
        ref.invalidate(aiCallDetailProvider(callId));
      }
    });
    final detail = ref.watch(aiCallDetailProvider(callId));
    final isAdmin = ref.watch(currentUserProvider)?.role.isAdmin ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI call'),
        actions: [
          if (isAdmin && (detail.value?.call.status.isActive ?? false))
            TextButton.icon(
              onPressed: () async {
                final ok = await showConfirmDialog(
                  context,
                  title: 'End AI call?',
                  message: 'The agent will be disconnected immediately.',
                  confirmLabel: 'End call',
                  destructive: true,
                );
                if (!ok) return;
                try {
                  await ref.read(aiRepositoryProvider).hangup(callId);
                  ref.invalidate(aiCallDetailProvider(callId));
                } catch (e) {
                  if (context.mounted) showSnack(context, errorMessage(e), error: true);
                }
              },
              icon: const Icon(Icons.call_end, color: AppColors.danger),
              label: const Text('End call'),
            ),
        ],
      ),
      body: AsyncValueView<AICallDetail>(
        value: detail,
        onRetry: () => ref.invalidate(aiCallDetailProvider(callId)),
        data: (d) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(aiCallDetailProvider(callId)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              ContentConstraint(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(call: d.call),
                    const SizedBox(height: 12),
                    if (d.handoff != null) ...[_HandoffCard(handoff: d.handoff!), const SizedBox(height: 12)],
                    if (d.intelligence != null)
                      _IntelligenceCard(intel: d.intelligence!)
                    else
                      InfoCard(
                        title: 'Call intelligence',
                        child: Text(
                          d.call.status.isActive
                              ? 'Generated automatically when the call ends.'
                              : 'No analysis for this call (it may not have connected).',
                        ),
                      ),
                    if (d.recordingId != null) ...[
                      const SizedBox(height: 12),
                      InfoCard(
                        title: 'Recording',
                        child: RecordingPlayer(recordingId: d.recordingId!),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _TranscriptCard(lines: d.transcript),
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

class _Header extends StatelessWidget {
  const _Header({required this.call});

  final AICall call;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: call.leadId == null ? null : () => context.go('/leads/${call.leadId}'),
                    child: Text(call.leadName ?? call.phoneMasked ?? 'Lead', style: theme.textTheme.titleLarge),
                  ),
                ),
                StatusChip.callStatus(call.status),
              ],
            ),
            const SizedBox(height: 8),
            KeyValueRow(icon: Icons.smart_toy_outlined, label: 'Agent', value: call.agentName),
            KeyValueRow(icon: Icons.campaign_outlined, label: 'Campaign', value: call.campaignName ?? 'Test call'),
            KeyValueRow(icon: Icons.phone_outlined, label: 'Number', value: call.phoneMasked),
            KeyValueRow(icon: Icons.schedule, label: 'Started', value: formatDateTime(call.startedAt)),
            KeyValueRow(icon: Icons.timer_outlined, label: 'Duration', value: formatDuration(call.durationSeconds)),
            KeyValueRow(icon: Icons.replay, label: 'Attempt', value: '${call.attempt}'),
            if (call.failureReason != null)
              KeyValueRow(icon: Icons.error_outline, label: 'Failure', value: call.failureReason),
          ],
        ),
      ),
    );
  }
}

class _HandoffCard extends StatelessWidget {
  const _HandoffCard({required this.handoff});

  final Handoff handoff;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.ai.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.support_agent, color: AppColors.ai),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Human handoff requested', style: Theme.of(context).textTheme.titleSmall),
                  if (handoff.reason != null) Text(handoff.reason!),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (handoff.notifiedUserName != null) 'Routed to ${handoff.notifiedUserName}',
                      handoff.transferred ? 'Live-transferred' : 'Marked for follow-up',
                      if (handoff.at != null) formatRelative(handoff.at),
                    ].join(' · '),
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

class _IntelligenceCard extends StatelessWidget {
  const _IntelligenceCard({required this.intel});

  final CallIntelligence intel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InfoCard(
      title: 'Call intelligence',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(intel.summary.isEmpty ? 'No summary.' : intel.summary)),
              const SizedBox(width: 12),
              ScoreGauge(score: intel.qualificationScore),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (intel.interestLevel != null) StatusChip.interest(intel.interestLevel!),
              if (intel.sentiment != null) StatusChip(label: 'Sentiment: ${intel.sentiment}', color: AppColors.neutral),
              if (intel.leadStatusSuggestion != null)
                StatusChip(label: 'Lead → ${intel.leadStatusSuggestion!.label}', color: AppColors.primary),
            ],
          ),
          if (intel.customerRequirements.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Customer requirements', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            for (final r in intel.customerRequirements)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(r)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 8),
          KeyValueRow(label: 'Budget', value: intel.budgetInformation ?? 'Not discussed'),
          KeyValueRow(label: 'Decision maker', value: intel.decisionMakerInformation),
          KeyValueRow(label: 'Next action', value: intel.nextAction),
          KeyValueRow(label: 'Follow-up', value: intel.followupRecommendation),
          if (intel.followupDate != null)
            KeyValueRow(label: 'Follow-up date', value: formatDateTime(intel.followupDate)),
        ],
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({required this.lines});

  final List<TranscriptLine> lines;

  String _offset(int ms) => formatTimer(Duration(milliseconds: ms));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InfoCard(
      title: 'Transcript',
      child: lines.isEmpty
          ? Text(
              'No transcript available.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          : Column(
              children: [
                for (final l in lines)
                  if (l.speaker == 'system')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        l.text,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    )
                  else
                    Align(
                      alignment: l.speaker == 'agent' ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 520),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: l.speaker == 'agent'
                              ? AppColors.ai.withValues(alpha: 0.1)
                              : theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${l.speaker == 'agent' ? 'AI agent' : 'Prospect'} · ${_offset(l.offsetMs)}',
                              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 2),
                            Text(l.text),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}
