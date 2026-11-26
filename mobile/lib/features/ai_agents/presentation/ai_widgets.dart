import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/ai_models.dart';

class AiCallTile extends StatelessWidget {
  const AiCallTile({super.key, required this.call});

  final AICall call;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: () => context.go('/ai/calls/${call.id}'),
      leading: CircleAvatar(
        backgroundColor: AppColors.ai.withValues(alpha: 0.12),
        foregroundColor: AppColors.ai,
        child: Icon(call.handoffRequested ? Icons.support_agent : Icons.smart_toy_outlined, size: 20),
      ),
      title: Text(call.leadName ?? call.phoneMasked ?? 'Lead', overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              call.agentName ?? 'Agent',
              if (call.campaignName != null) call.campaignName!,
              formatRelative(call.startedAt ?? call.createdAt),
              if (call.durationSeconds > 0) formatDuration(call.durationSeconds),
            ].join(' · '),
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (call.summary != null)
            Text(call.summary!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StatusChip.callStatus(call.status, dense: true),
          if (call.interestLevel != null) ...[
            const SizedBox(height: 4),
            StatusChip.interest(call.interestLevel!, dense: true),
          ],
        ],
      ),
    );
  }
}

/// Circular 0–100 gauge for the lead qualification score.
class ScoreGauge extends StatelessWidget {
  const ScoreGauge({super.key, required this.score, this.size = 84});

  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = score >= 70
        ? AppColors.success
        : score >= 40
        ? AppColors.warning
        : AppColors.neutral;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: (score.clamp(0, 100)) / 100,
            strokeWidth: 8,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
            strokeCap: StrokeCap.round,
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$score', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color)),
                Text('score', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VoiceStatusCard extends StatelessWidget {
  const VoiceStatusCard({super.key, required this.status});

  final VoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, ProviderStatus p, {String? extra}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            p.configured ? Icons.check_circle : Icons.cancel_outlined,
            size: 18,
            color: p.configured ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: 8),
          SizedBox(width: 90, child: Text(label, style: theme.textTheme.bodyMedium)),
          Expanded(
            child: Text(
              p.configured ? [p.provider ?? 'configured', ?p.model, ?extra].join(' · ') : 'Not configured',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Voice infrastructure', style: theme.textTheme.titleSmall)),
                StatusChip(
                  label: status.readyForLiveCalls ? 'Ready for live calls' : 'Setup incomplete',
                  color: status.readyForLiveCalls ? AppColors.success : AppColors.warning,
                ),
              ],
            ),
            const SizedBox(height: 8),
            row('Language model', status.llm),
            row('Speech-to-text', status.stt),
            row('Text-to-speech', status.tts),
            row(
              'Telephony',
              status.telephony,
              extra: status.supportsAiStreaming ? 'media streaming' : 'no media streaming',
            ),
            if (!status.readyForLiveCalls) ...[
              const SizedBox(height: 8),
              Text(
                'AI calls can\'t be placed until every component is configured on the server. '
                'Agents can still be edited and rehearsed in text.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
