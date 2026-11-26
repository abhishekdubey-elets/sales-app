/// Wire enums from docs/API.md. Every enum keeps the exact API string in
/// [value] and a human label in [label]. Unknown values fall back to a safe
/// default instead of throwing.
abstract interface class LabeledEnum {
  String get value;
  String get label;
}

T _from<T extends LabeledEnum>(List<T> values, Object? v, T fallback) {
  for (final e in values) {
    if (e.value == v) return e;
  }
  return fallback;
}

T? _fromOrNull<T extends LabeledEnum>(List<T> values, Object? v) {
  for (final e in values) {
    if (e.value == v) return e;
  }
  return null;
}

enum UserRole implements LabeledEnum {
  admin('admin', 'Admin'),
  manager('manager', 'Sales Manager'),
  executive('executive', 'Sales Executive');

  const UserRole(this.value, this.label);
  @override
  final String value;
  @override
  final String label;

  /// Unknown roles get the least privilege.
  static UserRole fromValue(Object? v) => _from(values, v, executive);

  bool get isAdmin => this == admin;
  bool get isManagerOrAdmin => this != executive;
}

enum LeadStatus implements LabeledEnum {
  newLead('new', 'New'),
  assigned('assigned', 'Assigned'),
  contacted('contacted', 'Contacted'),
  interested('interested', 'Interested'),
  followUp('follow_up', 'Follow-up'),
  meetingScheduled('meeting_scheduled', 'Meeting Scheduled'),
  converted('converted', 'Converted'),
  lost('lost', 'Lost');

  const LeadStatus(this.value, this.label);
  @override
  final String value;
  @override
  final String label;

  static LeadStatus fromValue(Object? v) => _from(values, v, newLead);
  static LeadStatus? fromValueOrNull(Object? v) => _fromOrNull(values, v);
}

enum LeadPriority implements LabeledEnum {
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High');

  const LeadPriority(this.value, this.label);
  @override
  final String value;
  @override
  final String label;

  static LeadPriority fromValue(Object? v) => _from(values, v, medium);
}

enum ConsentStatus implements LabeledEnum {
  unknown('unknown', 'Unknown'),
  granted('granted', 'Granted'),
  revoked('revoked', 'Revoked');

  const ConsentStatus(this.value, this.label);
  @override
  final String value;
  @override
  final String label;

  static ConsentStatus fromValue(Object? v) => _from(values, v, unknown);
}

enum CallStatus implements LabeledEnum {
  initiated('initiated', 'Initiated'),
  ringing('ringing', 'Ringing'),
  connected('connected', 'Connected'),
  completed('completed', 'Completed'),
  busy('busy', 'Busy'),
  notAnswered('not_answered', 'Not Answered'),
  failed('failed', 'Failed'),
  rejected('rejected', 'Rejected'),
  unknown('unknown', 'Unknown');

  const CallStatus(this.value, this.label);
  @override
  final String value;
  @override
  final String label;

  static CallStatus fromValue(Object? v) => _from(values, v, unknown);

  /// The provider is still working on the call.
  bool get isActive => this == initiated || this == ringing || this == connected;

  bool get isTerminal => this == completed || this == busy || this == notAnswered || this == failed || this == rejected;

  /// Statuses a user can filter by (excludes the client-only [unknown]).
  static List<CallStatus> get filterable => values.where((e) => e != unknown).toList();
}

enum CallOutcome implements LabeledEnum {
  interested('interested', 'Interested'),
  notInterested('not_interested', 'Not Interested'),
  followUpRequired('follow_up_required', 'Follow-up Required'),
  meetingScheduled('meeting_scheduled', 'Meeting Scheduled'),
  converted('converted', 'Converted'),
  wrongNumber('wrong_number', 'Wrong Number'),
  noResponse('no_response', 'No Response');

  const CallOutcome(this.value, this.label);
  @override
  final String value;
  @override
  final String label;

  static CallOutcome? fromValueOrNull(Object? v) => _fromOrNull(values, v);

  /// The lead status that usually follows this outcome (user can override).
  LeadStatus get suggestedLeadStatus => switch (this) {
    interested => LeadStatus.interested,
    notInterested => LeadStatus.lost,
    followUpRequired => LeadStatus.followUp,
    meetingScheduled => LeadStatus.meetingScheduled,
    converted => LeadStatus.converted,
    wrongNumber => LeadStatus.lost,
    noResponse => LeadStatus.contacted,
  };

  bool get suggestsFollowup => this == followUpRequired || this == meetingScheduled || this == interested;
}

enum CallDirection implements LabeledEnum {
  outbound('outbound', 'Outbound'),
  inbound('inbound', 'Inbound');

  const CallDirection(this.value, this.label);
  @override
  final String value;
  @override
  final String label;

  static CallDirection fromValue(Object? v) => _from(values, v, outbound);
}

enum CampaignStatus implements LabeledEnum {
  draft('draft', 'Draft'),
  running('running', 'Running'),
  paused('paused', 'Paused'),
  completed('completed', 'Completed'),
  stopped('stopped', 'Stopped');

  const CampaignStatus(this.value, this.label);
  @override
  final String value;
  @override
  final String label;

  static CampaignStatus fromValue(Object? v) => _from(values, v, draft);
}

enum CampaignLeadStatus implements LabeledEnum {
  pending('pending', 'Pending'),
  inProgress('in_progress', 'In Progress'),
  completed('completed', 'Completed'),
  failed('failed', 'Failed'),
  skipped('skipped', 'Skipped'),
  optedOut('opted_out', 'Opted Out');

  const CampaignLeadStatus(this.value, this.label);
  @override
  final String value;
  @override
  final String label;

  static CampaignLeadStatus fromValue(Object? v) => _from(values, v, pending);
}

enum InterestLevel implements LabeledEnum {
  high('high', 'High'),
  medium('medium', 'Medium'),
  low('low', 'Low');

  const InterestLevel(this.value, this.label);
  @override
  final String value;
  @override
  final String label;

  static InterestLevel? fromValueOrNull(Object? v) => _fromOrNull(values, v);
}

enum FollowupStatus implements LabeledEnum {
  pending('pending', 'Pending'),
  done('done', 'Done'),
  cancelled('cancelled', 'Cancelled');

  const FollowupStatus(this.value, this.label);
  @override
  final String value;
  @override
  final String label;

  static FollowupStatus fromValue(Object? v) => _from(values, v, pending);
}

enum NotificationType implements LabeledEnum {
  leadAssigned('lead_assigned', 'Lead assigned'),
  followupReminder('followup_reminder', 'Follow-up reminder'),
  aiQualifiedLead('ai_qualified_lead', 'AI-qualified lead'),
  handoffRequest('handoff_request', 'Handoff request'),
  campaignCompleted('campaign_completed', 'Campaign completed'),
  dailySummary('daily_summary', 'Daily summary'),
  system('system', 'System');

  const NotificationType(this.value, this.label);
  @override
  final String value;
  @override
  final String label;

  static NotificationType fromValue(Object? v) => _from(values, v, system);
}

enum AgentLanguage implements LabeledEnum {
  englishIndia('en-IN', 'English (India)'),
  hindiIndia('hi-IN', 'Hindi');

  const AgentLanguage(this.value, this.label);
  @override
  final String value;
  @override
  final String label;

  static AgentLanguage fromValue(Object? v) => _from(values, v, englishIndia);
}

enum DateRangePreset implements LabeledEnum {
  today('today', 'Today'),
  yesterday('yesterday', 'Yesterday'),
  thisWeek('this_week', 'This Week'),
  thisMonth('this_month', 'This Month'),
  custom('custom', 'Custom');

  const DateRangePreset(this.value, this.label);
  @override
  final String value;
  @override
  final String label;
}
