import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';

class CallNote {
  const CallNote({required this.id, required this.body, this.authorId, this.authorName, this.createdAt});

  factory CallNote.fromJson(Map<String, dynamic> j) => CallNote(
    id: asString(j['id']),
    body: asString(j['body']),
    authorId: asStringOrNull(j['author_id']),
    authorName: asStringOrNull(j['author_name']),
    createdAt: parseDate(j['created_at']),
  );

  final String id;
  final String body;
  final String? authorId;
  final String? authorName;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'body': body,
    'author_id': authorId,
    'author_name': authorName,
    'created_at': dateToJson(createdAt),
  };
}

class HumanCall {
  const HumanCall({
    required this.id,
    required this.status,
    this.direction = CallDirection.outbound,
    this.leadId,
    this.leadName,
    this.phoneNumber,
    this.salespersonId,
    this.salespersonName,
    this.provider,
    this.providerCallId,
    this.startedAt,
    this.answeredAt,
    this.endedAt,
    this.durationSeconds = 0,
    this.talkSeconds = 0,
    this.recordingId,
    this.outcome,
    this.followupAt,
    this.failureReason,
    this.notes = const [],
    this.createdAt,
  });

  factory HumanCall.fromJson(Map<String, dynamic> j) => HumanCall(
    id: asString(j['id']),
    direction: CallDirection.fromValue(j['direction']),
    leadId: asStringOrNull(j['lead_id']),
    leadName: asStringOrNull(j['lead_name']),
    phoneNumber: asStringOrNull(j['phone_number']),
    salespersonId: asStringOrNull(j['salesperson_id']),
    salespersonName: asStringOrNull(j['salesperson_name']),
    provider: asStringOrNull(j['provider']),
    providerCallId: asStringOrNull(j['provider_call_id']),
    status: CallStatus.fromValue(j['status']),
    startedAt: parseDate(j['started_at']),
    answeredAt: parseDate(j['answered_at']),
    endedAt: parseDate(j['ended_at']),
    durationSeconds: asInt(j['duration_seconds']),
    talkSeconds: asInt(j['talk_seconds']),
    recordingId: asStringOrNull(j['recording_id']),
    outcome: CallOutcome.fromValueOrNull(j['outcome']),
    followupAt: parseDate(j['followup_at']),
    failureReason: asStringOrNull(j['failure_reason']),
    notes: asList(j['notes'], CallNote.fromJson),
    createdAt: parseDate(j['created_at']),
  );

  final String id;
  final CallDirection direction;
  final String? leadId;
  final String? leadName;
  final String? phoneNumber;
  final String? salespersonId;
  final String? salespersonName;
  final String? provider;

  /// Set only once the telephony provider accepted the call request.
  final String? providerCallId;
  final CallStatus status;
  final DateTime? startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final int talkSeconds;
  final String? recordingId;
  final CallOutcome? outcome;
  final DateTime? followupAt;
  final String? failureReason;
  final List<CallNote> notes;
  final DateTime? createdAt;

  /// The provider confirmed it is handling this call.
  bool get isPlacedByProvider => providerCallId != null && providerCallId!.isNotEmpty;

  bool get needsDisposition => status.isTerminal && outcome == null && direction == CallDirection.outbound;

  String get displayName => leadName ?? phoneNumber ?? 'Unknown number';

  Map<String, dynamic> toJson() => {
    'id': id,
    'direction': direction.value,
    'lead_id': leadId,
    'lead_name': leadName,
    'phone_number': phoneNumber,
    'salesperson_id': salespersonId,
    'salesperson_name': salespersonName,
    'provider': provider,
    'provider_call_id': providerCallId,
    'status': status.value,
    'started_at': dateToJson(startedAt),
    'answered_at': dateToJson(answeredAt),
    'ended_at': dateToJson(endedAt),
    'duration_seconds': durationSeconds,
    'talk_seconds': talkSeconds,
    'recording_id': recordingId,
    'outcome': outcome?.value,
    'followup_at': dateToJson(followupAt),
    'failure_reason': failureReason,
    'notes': notes.map((n) => n.toJson()).toList(),
    'created_at': dateToJson(createdAt),
  };
}

class TelephonyStatus {
  const TelephonyStatus({
    this.provider,
    this.configured = false,
    this.callMode = 'bridge',
    this.supportsAiStreaming = false,
    this.supportsRecording = false,
    this.supportsInbound = false,
  });

  factory TelephonyStatus.fromJson(Map<String, dynamic> j) => TelephonyStatus(
    provider: asStringOrNull(j['provider']),
    configured: asBool(j['configured']),
    callMode: asString(j['call_mode'], 'bridge'),
    supportsAiStreaming: asBool(j['supports_ai_streaming']),
    supportsRecording: asBool(j['supports_recording']),
    supportsInbound: asBool(j['supports_inbound']),
  );

  final String? provider;
  final bool configured;

  /// `bridge` (provider rings the salesperson's phone) or `voip` (in-app audio).
  final String callMode;
  final bool supportsAiStreaming;
  final bool supportsRecording;
  final bool supportsInbound;

  bool get isVoip => callMode == 'voip';
}
