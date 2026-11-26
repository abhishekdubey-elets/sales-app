import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/formatters.dart';
import 'enums.dart';

/// `range=today|yesterday|this_week|this_month|custom` (+ `from`/`to` for custom).
class DateRangeFilter {
  const DateRangeFilter(this.preset, {this.from, this.to});

  const DateRangeFilter.today() : this(DateRangePreset.today);
  const DateRangeFilter.thisMonth() : this(DateRangePreset.thisMonth);

  final DateRangePreset preset;
  final DateTime? from;
  final DateTime? to;

  Map<String, dynamic> toQuery() => {
    'range': preset.value,
    if (preset == DateRangePreset.custom && from != null) 'from': formatApiDate(from!),
    if (preset == DateRangePreset.custom && to != null) 'to': formatApiDate(to!),
  };

  String get label {
    if (preset != DateRangePreset.custom || from == null || to == null) return preset.label;
    return '${formatDate(from)} – ${formatDate(to)}';
  }

  @override
  bool operator ==(Object other) =>
      other is DateRangeFilter && other.preset == preset && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(preset, from, to);
}

class DateRangeNotifier extends Notifier<DateRangeFilter> {
  DateRangeNotifier([this._initial = const DateRangeFilter.today()]);

  final DateRangeFilter _initial;

  @override
  DateRangeFilter build() => _initial;

  void set(DateRangeFilter value) => state = value;
}

/// Separate range selections per area so changing one screen doesn't move the others.
final dashboardRangeProvider = NotifierProvider<DateRangeNotifier, DateRangeFilter>(DateRangeNotifier.new);
final analyticsRangeProvider = NotifierProvider<DateRangeNotifier, DateRangeFilter>(
  () => DateRangeNotifier(const DateRangeFilter.thisMonth()),
);
final aiRangeProvider = NotifierProvider<DateRangeNotifier, DateRangeFilter>(
  () => DateRangeNotifier(const DateRangeFilter.thisMonth()),
);
final myStatsRangeProvider = NotifierProvider<DateRangeNotifier, DateRangeFilter>(
  () => DateRangeNotifier(const DateRangeFilter.thisMonth()),
);
