import '../../../core/utils/json.dart';

class OrgSettings {
  const OrgSettings({
    this.timezone = 'Asia/Kolkata',
    this.callingHoursStart = '09:00',
    this.callingHoursEnd = '21:00',
    this.callingDays = const [1, 2, 3, 4, 5, 6],
    this.recordingEnabled = false,
    this.recordingDisclosureText = '',
    this.aiDisclosureText = '',
    this.requireConsentForAiCalls = true,
    this.maskNumbersForExecutives = true,
    this.callingCreditsMinutes = 0,
    this.creditsUsedMinutes = 0,
    this.lowCreditThresholdMinutes = 0,
    this.dailySummaryTime = '19:00',
  });

  factory OrgSettings.fromJson(Map<String, dynamic> j) => OrgSettings(
    timezone: asString(j['timezone'], 'Asia/Kolkata'),
    callingHoursStart: asString(j['calling_hours_start'], '09:00'),
    callingHoursEnd: asString(j['calling_hours_end'], '21:00'),
    callingDays: asIntList(j['calling_days']),
    recordingEnabled: asBool(j['recording_enabled']),
    recordingDisclosureText: asString(j['recording_disclosure_text']),
    aiDisclosureText: asString(j['ai_disclosure_text']),
    requireConsentForAiCalls: asBool(j['require_consent_for_ai_calls'], true),
    maskNumbersForExecutives: asBool(j['mask_numbers_for_executives'], true),
    callingCreditsMinutes: asInt(j['calling_credits_minutes']),
    creditsUsedMinutes: asInt(j['credits_used_minutes']),
    lowCreditThresholdMinutes: asInt(j['low_credit_threshold_minutes']),
    dailySummaryTime: asString(j['daily_summary_time'], '19:00'),
  );

  final String timezone;
  final String callingHoursStart;
  final String callingHoursEnd;
  final List<int> callingDays;
  final bool recordingEnabled;
  final String recordingDisclosureText;
  final String aiDisclosureText;
  final bool requireConsentForAiCalls;
  final bool maskNumbersForExecutives;
  final int callingCreditsMinutes;
  final int creditsUsedMinutes;
  final int lowCreditThresholdMinutes;
  final String dailySummaryTime;

  Map<String, dynamic> toJson() => {
    'timezone': timezone,
    'calling_hours_start': callingHoursStart,
    'calling_hours_end': callingHoursEnd,
    'calling_days': callingDays,
    'recording_enabled': recordingEnabled,
    'recording_disclosure_text': recordingDisclosureText,
    'ai_disclosure_text': aiDisclosureText,
    'require_consent_for_ai_calls': requireConsentForAiCalls,
    'mask_numbers_for_executives': maskNumbersForExecutives,
    'calling_credits_minutes': callingCreditsMinutes,
    'low_credit_threshold_minutes': lowCreditThresholdMinutes,
    'daily_summary_time': dailySummaryTime,
  };
}

class AuditLog {
  const AuditLog({
    required this.id,
    required this.action,
    this.actorName,
    this.entityType,
    this.entityId,
    this.details,
    this.ipAddress,
    this.createdAt,
  });

  factory AuditLog.fromJson(Map<String, dynamic> j) {
    final d = j['details'];
    return AuditLog(
      id: asString(j['id']),
      action: asString(j['action']),
      actorName: asStringOrNull(j['actor_name']),
      entityType: asStringOrNull(j['entity_type']),
      entityId: asStringOrNull(j['entity_id']),
      details: d == null ? null : (d is Map ? d.entries.map((e) => '${e.key}: ${e.value}').join(', ') : d.toString()),
      ipAddress: asStringOrNull(j['ip_address']),
      createdAt: parseDate(j['created_at']),
    );
  }

  final String id;
  final String action;
  final String? actorName;
  final String? entityType;
  final String? entityId;
  final String? details;
  final String? ipAddress;
  final DateTime? createdAt;
}
