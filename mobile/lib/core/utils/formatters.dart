import 'package:intl/intl.dart';

/// "2h 10m", "12m 30s", "45s".
String formatDuration(int? totalSeconds) {
  final s = totalSeconds ?? 0;
  if (s <= 0) return '0s';
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
  if (m > 0) return sec > 0 ? '${m}m ${sec}s' : '${m}m';
  return '${sec}s';
}

/// Live call timer: "04:07" or "1:02:09".
String formatTimer(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

final _date = DateFormat('d MMM yyyy');
final _dateShort = DateFormat('d MMM');
final _time = DateFormat('h:mm a');
final _dateTime = DateFormat('d MMM yyyy, h:mm a');
final _apiDate = DateFormat('yyyy-MM-dd');

String formatDate(DateTime? d) => d == null ? '—' : _date.format(d.toLocal());
String formatTime(DateTime? d) => d == null ? '—' : _time.format(d.toLocal());
String formatDateTime(DateTime? d) => d == null ? '—' : _dateTime.format(d.toLocal());

/// Calendar date for query strings (`from`/`to`), in local time.
String formatApiDate(DateTime d) => _apiDate.format(d);

/// "just now", "5 min ago", "3 h ago", "Yesterday, 4:10 PM", "12 Mar", "in 2 h".
String formatRelative(DateTime? d, {DateTime? now}) {
  if (d == null) return '—';
  final local = d.toLocal();
  final ref = (now ?? DateTime.now()).toLocal();
  final diff = ref.difference(local);
  if (diff.isNegative) {
    final ahead = diff.abs();
    if (ahead.inMinutes < 1) return 'now';
    if (ahead.inMinutes < 60) return 'in ${ahead.inMinutes} min';
    if (ahead.inHours < 24) return 'in ${ahead.inHours} h';
    if (ahead.inDays < 7) return 'in ${ahead.inDays} d';
    return _sameYear(local, ref) ? _dateShort.format(local) : _date.format(local);
  }
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  final today = DateTime(ref.year, ref.month, ref.day);
  final day = DateTime(local.year, local.month, local.day);
  final dayDiff = today.difference(day).inDays;
  if (dayDiff == 0) return '${diff.inHours} h ago';
  if (dayDiff == 1) return 'Yesterday, ${_time.format(local)}';
  if (dayDiff < 7) return '${DateFormat('EEE').format(local)}, ${_time.format(local)}';
  return _sameYear(local, ref) ? _dateShort.format(local) : _date.format(local);
}

bool _sameYear(DateTime a, DateTime b) => a.year == b.year;

/// "56%" — returns "—" when there is no denominator.
String formatPercent(num part, num total) {
  if (total <= 0) return '—';
  return '${(part * 100 / total).round()}%';
}

/// 1234 → "1.2k", 1500000 → "1.5M".
String formatCompact(num n) => NumberFormat.compact().format(n);

String formatNumber(num n) => NumberFormat.decimalPattern('en_IN').format(n);

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}
