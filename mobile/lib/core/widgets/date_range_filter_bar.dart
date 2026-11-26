import 'package:flutter/material.dart';

import '../models/date_range_filter.dart';
import '../models/enums.dart';

/// Today / Yesterday / This Week / This Month / Custom (date range picker).
class DateRangeFilterBar extends StatelessWidget {
  const DateRangeFilterBar({super.key, required this.value, required this.onChanged, this.padding});

  final DateRangeFilter value;
  final ValueChanged<DateRangeFilter> onChanged;
  final EdgeInsets? padding;

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: value.preset == DateRangePreset.custom && value.from != null && value.to != null
          ? DateTimeRange(start: value.from!, end: value.to!)
          : DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
    );
    if (picked != null) {
      onChanged(DateRangeFilter(DateRangePreset.custom, from: picked.start, to: picked.end));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final p in DateRangePreset.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(p == DateRangePreset.custom && value.preset == p ? value.label : p.label),
                avatar: p == DateRangePreset.custom ? const Icon(Icons.date_range, size: 16) : null,
                selected: value.preset == p,
                onSelected: (_) {
                  if (p == DateRangePreset.custom) {
                    _pickCustom(context);
                  } else {
                    onChanged(DateRangeFilter(p));
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
