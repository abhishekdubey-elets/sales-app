import '../../../core/utils/json.dart';

class Team {
  const Team({
    required this.id,
    required this.name,
    this.department,
    this.managerId,
    this.managerName,
    this.memberCount = 0,
  });

  factory Team.fromJson(Map<String, dynamic> j) => Team(
    id: asString(j['id']),
    name: asString(j['name']),
    department: asStringOrNull(j['department']),
    managerId: asStringOrNull(j['manager_id']),
    managerName: asStringOrNull(j['manager_name']),
    memberCount: asInt(j['member_count']),
  );

  final String id;
  final String name;
  final String? department;
  final String? managerId;
  final String? managerName;
  final int memberCount;
}
