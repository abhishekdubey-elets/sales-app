import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';

class Lead {
  const Lead({
    required this.id,
    required this.fullName,
    required this.phone,
    this.phoneMasked,
    this.companyName,
    this.alternatePhone,
    this.email,
    this.designation,
    this.industry,
    this.location,
    this.source,
    this.assignedToId,
    this.assignedToName,
    this.status = LeadStatus.newLead,
    this.priority = LeadPriority.medium,
    this.lastCalledAt,
    this.nextFollowupAt,
    this.remarks,
    this.consentStatus = ConsentStatus.unknown,
    this.optedOut = false,
    this.isFavourite = false,
    this.callCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory Lead.fromJson(Map<String, dynamic> j) => Lead(
    id: asString(j['id']),
    fullName: asString(j['full_name']),
    companyName: asStringOrNull(j['company_name']),
    phone: asString(j['phone']),
    phoneMasked: asStringOrNull(j['phone_masked']),
    alternatePhone: asStringOrNull(j['alternate_phone']),
    email: asStringOrNull(j['email']),
    designation: asStringOrNull(j['designation']),
    industry: asStringOrNull(j['industry']),
    location: asStringOrNull(j['location']),
    source: asStringOrNull(j['source']),
    assignedToId: asStringOrNull(j['assigned_to_id']),
    assignedToName: asStringOrNull(j['assigned_to_name']),
    status: LeadStatus.fromValue(j['status']),
    priority: LeadPriority.fromValue(j['priority']),
    lastCalledAt: parseDate(j['last_called_at']),
    nextFollowupAt: parseDate(j['next_followup_at']),
    remarks: asStringOrNull(j['remarks']),
    consentStatus: ConsentStatus.fromValue(j['consent_status']),
    optedOut: asBool(j['opted_out']),
    isFavourite: asBool(j['is_favourite']),
    callCount: asInt(j['call_count']),
    createdAt: parseDate(j['created_at']),
    updatedAt: parseDate(j['updated_at']),
  );

  final String id;
  final String fullName;
  final String? companyName;

  /// May already be masked for executives (see `mask_numbers_for_executives`).
  final String phone;
  final String? phoneMasked;
  final String? alternatePhone;
  final String? email;
  final String? designation;
  final String? industry;
  final String? location;
  final String? source;
  final String? assignedToId;
  final String? assignedToName;
  final LeadStatus status;
  final LeadPriority priority;
  final DateTime? lastCalledAt;
  final DateTime? nextFollowupAt;
  final String? remarks;
  final ConsentStatus consentStatus;
  final bool optedOut;
  final bool isFavourite;
  final int callCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayPhone => phoneMasked ?? phone;

  String get subtitle => [designation, companyName].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  Lead copyWith({bool? isFavourite, LeadStatus? status, LeadPriority? priority, bool? optedOut}) => Lead(
    id: id,
    fullName: fullName,
    companyName: companyName,
    phone: phone,
    phoneMasked: phoneMasked,
    alternatePhone: alternatePhone,
    email: email,
    designation: designation,
    industry: industry,
    location: location,
    source: source,
    assignedToId: assignedToId,
    assignedToName: assignedToName,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    lastCalledAt: lastCalledAt,
    nextFollowupAt: nextFollowupAt,
    remarks: remarks,
    consentStatus: consentStatus,
    optedOut: optedOut ?? this.optedOut,
    isFavourite: isFavourite ?? this.isFavourite,
    callCount: callCount,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'company_name': companyName,
    'phone': phone,
    'phone_masked': phoneMasked,
    'alternate_phone': alternatePhone,
    'email': email,
    'designation': designation,
    'industry': industry,
    'location': location,
    'source': source,
    'assigned_to_id': assignedToId,
    'assigned_to_name': assignedToName,
    'status': status.value,
    'priority': priority.value,
    'last_called_at': dateToJson(lastCalledAt),
    'next_followup_at': dateToJson(nextFollowupAt),
    'remarks': remarks,
    'consent_status': consentStatus.value,
    'opted_out': optedOut,
    'is_favourite': isFavourite,
    'call_count': callCount,
    'created_at': dateToJson(createdAt),
    'updated_at': dateToJson(updatedAt),
  };
}

class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.type,
    required this.title,
    this.at,
    this.description,
    this.actorName,
    this.refId,
  });

  factory TimelineItem.fromJson(Map<String, dynamic> j) => TimelineItem(
    id: asString(j['id']),
    type: asString(j['type'], 'note'),
    at: parseDate(j['at']),
    title: asString(j['title']),
    description: asStringOrNull(j['description']),
    actorName: asStringOrNull(j['actor_name']),
    refId: asStringOrNull(j['ref_id']),
  );

  final String id;

  /// created|assigned|status_changed|human_call|ai_call|note|followup|handoff|opt_out|imported
  final String type;
  final DateTime? at;
  final String title;
  final String? description;
  final String? actorName;
  final String? refId;
}

/// Row of `/leads/{id}/calls`: human and AI calls side by side.
/// API.md only names the type, so this parser accepts the union of HumanCall and AICall fields.
class UnifiedCall {
  const UnifiedCall({
    required this.id,
    required this.origin,
    required this.status,
    this.salespersonName,
    this.agentName,
    this.campaignName,
    this.outcome,
    this.interestLevel,
    this.startedAt,
    this.durationSeconds = 0,
    this.summary,
    this.direction,
  });

  factory UnifiedCall.fromJson(Map<String, dynamic> j) {
    final origin =
        asStringOrNull(j['origin']) ??
        asStringOrNull(j['origin_type']) ??
        (j['agent_id'] != null || j['ai_agent_id'] != null ? 'ai' : 'human');
    return UnifiedCall(
      id: asString(j['id'] ?? j['call_id']),
      origin: origin,
      status: CallStatus.fromValue(j['status']),
      salespersonName: asStringOrNull(j['salesperson_name']),
      agentName: asStringOrNull(j['agent_name']),
      campaignName: asStringOrNull(j['campaign_name']),
      outcome: CallOutcome.fromValueOrNull(j['outcome']),
      interestLevel: InterestLevel.fromValueOrNull(j['interest_level']),
      startedAt: parseDate(j['started_at'] ?? j['created_at']),
      durationSeconds: asInt(j['duration_seconds']),
      summary: asStringOrNull(j['summary']),
      direction: asStringOrNull(j['direction']),
    );
  }

  final String id;

  /// `human` or `ai`.
  final String origin;
  final CallStatus status;
  final String? salespersonName;
  final String? agentName;
  final String? campaignName;
  final CallOutcome? outcome;
  final InterestLevel? interestLevel;
  final DateTime? startedAt;
  final int durationSeconds;
  final String? summary;
  final String? direction;

  bool get isAi => origin == 'ai';
}

class DuplicateCheck {
  const DuplicateCheck({required this.duplicate, this.leadId, this.matchedOn});

  factory DuplicateCheck.fromJson(Map<String, dynamic> j) => DuplicateCheck(
    duplicate: asBool(j['duplicate']),
    leadId: asStringOrNull(j['lead_id']),
    matchedOn: asStringOrNull(j['matched_on']),
  );

  final bool duplicate;
  final String? leadId;
  final String? matchedOn;
}

class ImportRowError {
  const ImportRowError({required this.row, required this.error});

  factory ImportRowError.fromJson(Map<String, dynamic> j) =>
      ImportRowError(row: asInt(j['row']), error: asString(j['error']));

  final int row;
  final String error;
}

class ImportResult {
  const ImportResult({
    required this.totalRows,
    required this.created,
    required this.duplicates,
    required this.errors,
    this.leadIds = const [],
  });

  factory ImportResult.fromJson(Map<String, dynamic> j) => ImportResult(
    totalRows: asInt(j['total_rows']),
    created: asInt(j['created']),
    duplicates: asInt(j['duplicates']),
    errors: asList(j['errors'], ImportRowError.fromJson),
    leadIds: asStringList(j['lead_ids']),
  );

  final int totalRows;
  final int created;
  final int duplicates;
  final List<ImportRowError> errors;
  final List<String> leadIds;
}
