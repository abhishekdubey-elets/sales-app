import 'package:flutter/material.dart';

import '../models/enums.dart';
import 'app_theme.dart';

Color callStatusColor(CallStatus s) => switch (s) {
  CallStatus.initiated => AppColors.neutral,
  CallStatus.ringing => AppColors.warning,
  CallStatus.connected => AppColors.success,
  CallStatus.completed => AppColors.primary,
  CallStatus.busy => AppColors.warning,
  CallStatus.notAnswered => AppColors.warning,
  CallStatus.failed => AppColors.danger,
  CallStatus.rejected => AppColors.danger,
  CallStatus.unknown => AppColors.neutral,
};

IconData callStatusIcon(CallStatus s) => switch (s) {
  CallStatus.initiated => Icons.schedule,
  CallStatus.ringing => Icons.ring_volume,
  CallStatus.connected => Icons.call,
  CallStatus.completed => Icons.call_end,
  CallStatus.busy => Icons.phone_locked,
  CallStatus.notAnswered => Icons.phone_missed,
  CallStatus.failed => Icons.error_outline,
  CallStatus.rejected => Icons.phone_disabled,
  CallStatus.unknown => Icons.help_outline,
};

Color leadStatusColor(LeadStatus s) => switch (s) {
  LeadStatus.newLead => AppColors.info,
  LeadStatus.assigned => AppColors.teal,
  LeadStatus.contacted => AppColors.neutral,
  LeadStatus.interested => AppColors.success,
  LeadStatus.followUp => AppColors.warning,
  LeadStatus.meetingScheduled => AppColors.ai,
  LeadStatus.converted => AppColors.success,
  LeadStatus.lost => AppColors.danger,
};

Color outcomeColor(CallOutcome o) => switch (o) {
  CallOutcome.interested => AppColors.success,
  CallOutcome.notInterested => AppColors.danger,
  CallOutcome.followUpRequired => AppColors.warning,
  CallOutcome.meetingScheduled => AppColors.ai,
  CallOutcome.converted => AppColors.success,
  CallOutcome.wrongNumber => AppColors.neutral,
  CallOutcome.noResponse => AppColors.neutral,
};

Color priorityColor(LeadPriority p) => switch (p) {
  LeadPriority.high => AppColors.danger,
  LeadPriority.medium => AppColors.warning,
  LeadPriority.low => AppColors.neutral,
};

Color campaignStatusColor(CampaignStatus s) => switch (s) {
  CampaignStatus.draft => AppColors.neutral,
  CampaignStatus.running => AppColors.success,
  CampaignStatus.paused => AppColors.warning,
  CampaignStatus.completed => AppColors.primary,
  CampaignStatus.stopped => AppColors.danger,
};

Color campaignLeadStatusColor(CampaignLeadStatus s) => switch (s) {
  CampaignLeadStatus.pending => AppColors.neutral,
  CampaignLeadStatus.inProgress => AppColors.warning,
  CampaignLeadStatus.completed => AppColors.success,
  CampaignLeadStatus.failed => AppColors.danger,
  CampaignLeadStatus.skipped => AppColors.neutral,
  CampaignLeadStatus.optedOut => AppColors.danger,
};

Color interestColor(InterestLevel l) => switch (l) {
  InterestLevel.high => AppColors.success,
  InterestLevel.medium => AppColors.warning,
  InterestLevel.low => AppColors.neutral,
};

Color followupStatusColor(FollowupStatus s) => switch (s) {
  FollowupStatus.pending => AppColors.warning,
  FollowupStatus.done => AppColors.success,
  FollowupStatus.cancelled => AppColors.neutral,
};
