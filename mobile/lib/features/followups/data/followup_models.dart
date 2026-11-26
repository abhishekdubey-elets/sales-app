import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';

class Followup {
  const Followup({
    required this.id,
    required this.status,
    this.leadId,
    this.leadName,
    this.assignedToId,
    this.assignedToName,
    this.dueAt,
    this.note,
    this.source = 'manual',
    this.createdAt,
  });

  factory Followup.fromJson(Map<String, dynamic> j) => Followup(
    id: asString(j['id']),
    leadId: asStringOrNull(j['lead_id']),
    leadName: asStringOrNull(j['lead_name']),
    assignedToId: asStringOrNull(j['assigned_to_id']),
    assignedToName: asStringOrNull(j['assigned_to_name']),
    dueAt: parseDate(j['due_at']),
    status: FollowupStatus.fromValue(j['status']),
    note: asStringOrNull(j['note']),
    source: asString(j['source'], 'manual'),
    createdAt: parseDate(j['created_at']),
  );

  final String id;
  final String? leadId;
  final String? leadName;
  final String? assignedToId;
  final String? assignedToName;
  final DateTime? dueAt;
  final FollowupStatus status;
  final String? note;

  /// human_call | ai_call | manual
  final String source;
  final DateTime? createdAt;

  bool get isOverdue => status == FollowupStatus.pending && dueAt != null && dueAt!.isBefore(DateTime.now());
  bool get fromAi => source == 'ai_call';
}
