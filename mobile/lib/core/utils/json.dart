// Lenient JSON readers. The backend is the source of truth, but the app must not
// crash on a missing or slightly different field, so every model goes through these.

DateTime? parseDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

String? dateToJson(DateTime? d) => d?.toUtc().toIso8601String();

int asInt(Object? v, [int fallback = 0]) => asIntOrNull(v) ?? fallback;

int? asIntOrNull(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt();
  return null;
}

double asDouble(Object? v, [double fallback = 0]) => asDoubleOrNull(v) ?? fallback;

double? asDoubleOrNull(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

String asString(Object? v, [String fallback = '']) => v?.toString() ?? fallback;

String? asStringOrNull(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

bool asBool(Object? v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.toLowerCase() == 'true';
  return fallback;
}

Map<String, dynamic> asMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

Map<String, dynamic>? asMapOrNull(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

List<T> asList<T>(Object? v, T Function(Map<String, dynamic>) parse) {
  if (v is! List) return <T>[];
  return v.whereType<Map>().map((e) => parse(Map<String, dynamic>.from(e))).toList();
}

List<String> asStringList(Object? v) =>
    v is List ? v.where((e) => e != null).map((e) => e.toString()).toList() : <String>[];

List<int> asIntList(Object? v) => v is List ? v.map(asIntOrNull).whereType<int>().toList() : <int>[];

/// Drops null values so PATCH bodies and query strings stay minimal.
Map<String, dynamic> compact(Map<String, dynamic> m) =>
    Map<String, dynamic>.fromEntries(m.entries.where((e) => e.value != null && e.value != ''));
