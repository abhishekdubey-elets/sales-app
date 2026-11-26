import 'package:elets_salescall_ai/core/models/date_range_filter.dart';
import 'package:elets_salescall_ai/core/models/enums.dart';
import 'package:elets_salescall_ai/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDuration', () {
    test('matches the leaderboard style', () {
      expect(formatDuration(7800), '2h 10m');
      expect(formatDuration(6000), '1h 40m');
      expect(formatDuration(3600), '1h');
      expect(formatDuration(750), '12m 30s');
      expect(formatDuration(120), '2m');
      expect(formatDuration(45), '45s');
      expect(formatDuration(0), '0s');
      expect(formatDuration(null), '0s');
    });
  });

  test('formatTimer pads minutes and seconds', () {
    expect(formatTimer(const Duration(seconds: 247)), '04:07');
    expect(formatTimer(const Duration(hours: 1, minutes: 2, seconds: 9)), '1:02:09');
    expect(formatTimer(const Duration(seconds: -5)), '00:00');
  });

  group('formatRelative', () {
    final now = DateTime(2026, 11, 26, 15, 0);
    test('recent past', () {
      expect(formatRelative(now.subtract(const Duration(seconds: 10)), now: now), 'just now');
      expect(formatRelative(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
      expect(formatRelative(now.subtract(const Duration(hours: 3)), now: now), '3 h ago');
      expect(formatRelative(DateTime(2026, 11, 25, 16, 10), now: now), 'Yesterday, 4:10 PM');
    });
    test('future', () {
      expect(formatRelative(now.add(const Duration(minutes: 30)), now: now), 'in 30 min');
      expect(formatRelative(now.add(const Duration(hours: 2, minutes: 5)), now: now), 'in 2 h');
    });
    test('older dates', () {
      expect(formatRelative(DateTime(2026, 3, 12, 9), now: now), '12 Mar');
      expect(formatRelative(DateTime(2025, 3, 12, 9), now: now), '12 Mar 2025');
      expect(formatRelative(null), '—');
    });
  });

  test('formatPercent and initials', () {
    expect(formatPercent(25, 45), '56%');
    expect(formatPercent(1, 0), '—');
    expect(initials('Rahul Kumar Verma'), 'RV');
    expect(initials('priya'), 'P');
    expect(initials('  '), '?');
  });

  test('DateRangeFilter builds API query parameters', () {
    expect(const DateRangeFilter.today().toQuery(), {'range': 'today'});
    final custom = DateRangeFilter(DateRangePreset.custom, from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 26));
    expect(custom.toQuery(), {'range': 'custom', 'from': '2026-11-01', 'to': '2026-11-26'});
    expect(custom, DateRangeFilter(DateRangePreset.custom, from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 26)));
  });
}
