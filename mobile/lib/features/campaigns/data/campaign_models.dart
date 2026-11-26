import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';

class CampaignSchedule {
  const CampaignSchedule({
    this.timezone = 'Asia/Kolkata',
    this.daysOfWeek = const [1, 2, 3, 4, 5, 6],
    this.startTime = '10:00',
    this.endTime = '18:00',
    this.startDate,
    this.endDate,
  });

  factory CampaignSchedule.fromJson(Map<String, dynamic> j) => CampaignSchedule(
    timezone: asString(j['timezone'], 'Asia/Kolkata'),
    daysOfWeek: asIntList(j['days_of_week']),
    startTime: asString(j['start_time'], '10:00'),
    endTime: asString(j['end_time'], '18:00'),
    startDate: asStringOrNull(j['start_date']),
    endDate: asStringOrNull(j['end_date']),
  );

  final String timezone;

  /// ISO weekdays, 1 = Monday … 7 = Sunday.
  final List<int> daysOfWeek;

  /// "HH:MM" in [timezone].
  final String startTime;
  final String endTime;

  /// "YYYY-MM-DD" or null.
  final String? startDate;
  final String? endDate;

  CampaignSchedule copyWith({
    String? timezone,
    List<int>? daysOfWeek,
    String? startTime,
    String? endTime,
    String? startDate,
    String? endDate,
    bool clearStartDate = false,
    bool clearEndDate = false,
  }) => CampaignSchedule(
    timezone: timezone ?? this.timezone,
    daysOfWeek: daysOfWeek ?? this.daysOfWeek,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    startDate: clearStartDate ? null : (startDate ?? this.startDate),
    endDate: clearEndDate ? null : (endDate ?? this.endDate),
  );

  Map<String, dynamic> toJson() => {
    'timezone': timezone,
    'days_of_week': daysOfWeek,
    'start_time': startTime,
    'end_time': endTime,
    'start_date': startDate,
    'end_date': endDate,
  };

  static const dayLabels = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};

  String get daysLabel {
    final sorted = [...daysOfWeek]..sort();
    return sorted.map((d) => dayLabels[d] ?? '?').join(', ');
  }
}

class CampaignStats {
  const CampaignStats({
    this.totalLeads = 0,
    this.pending = 0,
    this.inProgress = 0,
    this.attempted = 0,
    this.connected = 0,
    this.notAnswered = 0,
    this.failed = 0,
    this.interested = 0,
    this.qualified = 0,
    this.followups = 0,
    this.conversions = 0,
    this.handoffs = 0,
    this.optedOut = 0,
  });

  factory CampaignStats.fromJson(Map<String, dynamic> j) => CampaignStats(
    totalLeads: asInt(j['total_leads']),
    pending: asInt(j['pending']),
    inProgress: asInt(j['in_progress']),
    attempted: asInt(j['attempted']),
    connected: asInt(j['connected']),
    notAnswered: asInt(j['not_answered']),
    failed: asInt(j['failed']),
    interested: asInt(j['interested']),
    qualified: asInt(j['qualified']),
    followups: asInt(j['followups']),
    conversions: asInt(j['conversions']),
    handoffs: asInt(j['handoffs']),
    optedOut: asInt(j['opted_out']),
  );

  final int totalLeads;
  final int pending;
  final int inProgress;
  final int attempted;
  final int connected;
  final int notAnswered;
  final int failed;
  final int interested;
  final int qualified;
  final int followups;
  final int conversions;
  final int handoffs;
  final int optedOut;

  /// Share of leads that are no longer waiting to be called.
  double get progress {
    if (totalLeads <= 0) return 0;
    final done = totalLeads - pending - inProgress;
    return (done / totalLeads).clamp(0, 1).toDouble();
  }
}

class Campaign {
  const Campaign({
    required this.id,
    required this.name,
    required this.status,
    this.description,
    this.agentId,
    this.agentName,
    this.schedule = const CampaignSchedule(),
    this.maxAttempts = 3,
    this.retryDelayMinutes = 60,
    this.maxConcurrentCalls = 2,
    this.callsPerMinute = 4,
    this.createdAt,
    this.startedAt,
    this.completedAt,
    this.stats = const CampaignStats(),
  });

  factory Campaign.fromJson(Map<String, dynamic> j) => Campaign(
    id: asString(j['id']),
    name: asString(j['name']),
    description: asStringOrNull(j['description']),
    agentId: asStringOrNull(j['agent_id']),
    agentName: asStringOrNull(j['agent_name']),
    status: CampaignStatus.fromValue(j['status']),
    schedule: CampaignSchedule.fromJson(asMap(j['schedule'])),
    maxAttempts: asInt(j['max_attempts'], 3),
    retryDelayMinutes: asInt(j['retry_delay_minutes'], 60),
    maxConcurrentCalls: asInt(j['max_concurrent_calls'], 2),
    callsPerMinute: asInt(j['calls_per_minute'], 4),
    createdAt: parseDate(j['created_at']),
    startedAt: parseDate(j['started_at']),
    completedAt: parseDate(j['completed_at']),
    stats: CampaignStats.fromJson(asMap(j['stats'])),
  );

  final String id;
  final String name;
  final String? description;
  final String? agentId;
  final String? agentName;
  final CampaignStatus status;
  final CampaignSchedule schedule;
  final int maxAttempts;
  final int retryDelayMinutes;
  final int maxConcurrentCalls;
  final int callsPerMinute;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final CampaignStats stats;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'agent_id': agentId,
    'agent_name': agentName,
    'status': status.value,
    'schedule': schedule.toJson(),
    'max_attempts': maxAttempts,
    'retry_delay_minutes': retryDelayMinutes,
    'max_concurrent_calls': maxConcurrentCalls,
    'calls_per_minute': callsPerMinute,
    'created_at': dateToJson(createdAt),
    'started_at': dateToJson(startedAt),
    'completed_at': dateToJson(completedAt),
  };
}

class CampaignLead {
  const CampaignLead({
    required this.id,
    required this.status,
    this.leadId,
    this.leadName,
    this.companyName,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastCallStatus,
    this.outcome,
    this.interestLevel,
    this.lastAiCallId,
  });

  factory CampaignLead.fromJson(Map<String, dynamic> j) => CampaignLead(
    id: asString(j['id']),
    leadId: asStringOrNull(j['lead_id']),
    leadName: asStringOrNull(j['lead_name']),
    companyName: asStringOrNull(j['company_name']),
    status: CampaignLeadStatus.fromValue(j['status']),
    attempts: asInt(j['attempts']),
    nextAttemptAt: parseDate(j['next_attempt_at']),
    lastCallStatus: j['last_call_status'] == null ? null : CallStatus.fromValue(j['last_call_status']),
    outcome: asStringOrNull(j['outcome']),
    interestLevel: InterestLevel.fromValueOrNull(j['interest_level']),
    lastAiCallId: asStringOrNull(j['last_ai_call_id']),
  );

  final String id;
  final String? leadId;
  final String? leadName;
  final String? companyName;
  final CampaignLeadStatus status;
  final int attempts;
  final DateTime? nextAttemptAt;
  final CallStatus? lastCallStatus;
  final String? outcome;
  final InterestLevel? interestLevel;
  final String? lastAiCallId;
}

class CampaignLog {
  const CampaignLog({
    required this.id,
    required this.level,
    required this.event,
    required this.message,
    this.leadId,
    this.aiCallId,
    this.createdAt,
  });

  factory CampaignLog.fromJson(Map<String, dynamic> j) => CampaignLog(
    id: asString(j['id']),
    level: asString(j['level'], 'info'),
    event: asString(j['event']),
    message: asString(j['message']),
    leadId: asStringOrNull(j['lead_id']),
    aiCallId: asStringOrNull(j['ai_call_id']),
    createdAt: parseDate(j['created_at']),
  );

  final String id;

  /// info | warning | error
  final String level;
  final String event;
  final String message;
  final String? leadId;
  final String? aiCallId;
  final DateTime? createdAt;
}
