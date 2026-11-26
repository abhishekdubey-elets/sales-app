import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../theme/status_colors.dart';

/// Small rounded label with a semantic colour.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, this.icon, this.dense = false});

  StatusChip.callStatus(CallStatus status, {Key? key, bool dense = false})
    : this(key: key, label: status.label, color: callStatusColor(status), icon: callStatusIcon(status), dense: dense);

  StatusChip.leadStatus(LeadStatus status, {Key? key, bool dense = false})
    : this(key: key, label: status.label, color: leadStatusColor(status), dense: dense);

  StatusChip.outcome(CallOutcome outcome, {Key? key, bool dense = false})
    : this(key: key, label: outcome.label, color: outcomeColor(outcome), dense: dense);

  StatusChip.priority(LeadPriority priority, {Key? key, bool dense = false})
    : this(key: key, label: priority.label, color: priorityColor(priority), icon: Icons.flag, dense: dense);

  StatusChip.campaign(CampaignStatus status, {Key? key, bool dense = false})
    : this(key: key, label: status.label, color: campaignStatusColor(status), dense: dense);

  StatusChip.campaignLead(CampaignLeadStatus status, {Key? key, bool dense = false})
    : this(key: key, label: status.label, color: campaignLeadStatusColor(status), dense: dense);

  StatusChip.interest(InterestLevel level, {Key? key, bool dense = false})
    : this(key: key, label: '${level.label} interest', color: interestColor(level), dense: dense);

  StatusChip.followup(FollowupStatus status, {Key? key, bool dense = false})
    : this(key: key, label: status.label, color: followupStatusColor(status), dense: dense);

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700, letterSpacing: 0.1);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: dense ? 11 : 13, color: color), const SizedBox(width: 4)],
          Text(label, style: style),
        ],
      ),
    );
  }
}
