import '../../../core/utils/json.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.data = const {},
    this.readAt,
    this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: asString(j['id']),
    type: asString(j['type'], 'system'),
    title: asString(j['title']),
    body: asStringOrNull(j['body']),
    data: asMap(j['data']),
    readAt: parseDate(j['read_at']),
    createdAt: parseDate(j['created_at']),
  );

  final String id;
  final String type;
  final String title;
  final String? body;
  final Map<String, dynamic> data;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isRead => readAt != null;
}
