import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/state_views.dart';
import '../data/analytics_models.dart';

class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});

  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      children: [
        for (final (label, color) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
      ],
    );
  }
}

Widget _axisLabel(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: 6),
  child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10)),
);

/// Human vs AI calls per day.
class CallsByDateChart extends StatelessWidget {
  const CallsByDateChart({super.key, required this.points});

  final List<CallsByDatePoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(
        height: 200,
        child: EmptyState(title: 'No calls in this period', icon: Icons.show_chart),
      );
    }
    final theme = Theme.of(context);
    final maxY = points.fold<int>(0, (m, p) => max(m, max(p.human, p.ai)));
    final step = max(1, (points.length / 6).ceil());
    LineChartBarData line(List<FlSpot> spots, Color color) => LineChartBarData(
      spots: spots,
      isCurved: true,
      preventCurveOverShooting: true,
      color: color,
      barWidth: 2.5,
      dotData: FlDotData(show: points.length <= 14),
      belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: (maxY * 1.2).ceilToDouble().clamp(4, double.infinity),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: theme.colorScheme.outlineVariant, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    getTitlesWidget: (v, meta) =>
                        v % 1 == 0 ? _axisLabel(context, v.toInt().toString()) : const SizedBox(),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 24,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= points.length || i % step != 0) return const SizedBox();
                      return _axisLabel(context, DateFormat('d MMM').format(points[i].date));
                    },
                  ),
                ),
              ),
              lineBarsData: [
                line([
                  for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].human.toDouble()),
                ], AppColors.primary),
                line([
                  for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].ai.toDouble()),
                ], AppColors.ai),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const ChartLegend(items: [('Human calls', AppColors.primary), ('AI calls', AppColors.ai)]),
      ],
    );
  }
}

/// Grouped bars comparing the human and AI channels.
class HumanVsAiChart extends StatelessWidget {
  const HumanVsAiChart({super.key, required this.data});

  final HumanVsAi data;

  @override
  Widget build(BuildContext context) {
    final metrics = <(String, int, int)>[
      ('Calls', data.human.calls, data.ai.calls),
      ('Connected', data.human.connected, data.ai.connected),
      ('Interested', data.human.interested, data.ai.interested),
      ('Qualified', data.human.qualified, data.ai.qualified),
      ('Converted', data.human.converted, data.ai.converted),
    ];
    final maxY = metrics.fold<int>(0, (m, e) => max(m, max(e.$2, e.$3)));
    if (maxY == 0) {
      return const SizedBox(
        height: 180,
        child: EmptyState(title: 'No activity yet', icon: Icons.bar_chart),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: (maxY * 1.2).ceilToDouble(),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: Theme.of(context).colorScheme.outlineVariant, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    getTitlesWidget: (v, meta) =>
                        v % 1 == 0 && v != meta.max ? _axisLabel(context, formatCompact(v)) : const SizedBox(),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      return i >= 0 && i < metrics.length ? _axisLabel(context, metrics[i].$1) : const SizedBox();
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < metrics.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: metrics[i].$2.toDouble(),
                        color: AppColors.primary,
                        width: 12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      BarChartRodData(
                        toY: metrics[i].$3.toDouble(),
                        color: AppColors.ai,
                        width: 12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const ChartLegend(items: [('Human', AppColors.primary), ('AI', AppColors.ai)]),
      ],
    );
  }
}

/// Horizontal-ish bar chart of calls vs connected per salesperson (top 8).
class SalespersonBarChart extends StatelessWidget {
  const SalespersonBarChart({super.key, required this.rows});

  final List<LeaderboardRow> rows;

  @override
  Widget build(BuildContext context) {
    final top = [...rows]..sort((a, b) => b.calls.compareTo(a.calls));
    final shown = top.take(8).toList();
    if (shown.isEmpty || shown.first.calls == 0) {
      return const SizedBox(
        height: 180,
        child: EmptyState(title: 'No calls by salespeople yet', icon: Icons.bar_chart),
      );
    }
    final maxY = shown.first.calls.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              maxY: (maxY * 1.2).ceilToDouble(),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: Theme.of(context).colorScheme.outlineVariant, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    getTitlesWidget: (v, meta) =>
                        v % 1 == 0 && v != meta.max ? _axisLabel(context, formatCompact(v)) : const SizedBox(),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= shown.length) return const SizedBox();
                      return _axisLabel(context, shown[i].name.split(' ').first);
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < shown.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 3,
                    barRods: [
                      BarChartRodData(
                        toY: shown[i].calls.toDouble(),
                        color: AppColors.primary,
                        width: 10,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      BarChartRodData(
                        toY: shown[i].connected.toDouble(),
                        color: AppColors.success,
                        width: 10,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const ChartLegend(items: [('Calls', AppColors.primary), ('Connected', AppColors.success)]),
      ],
    );
  }
}

/// Ranked table: Salesperson | Calls | Connected | Duration | Conversions.
class LeaderboardTable extends StatelessWidget {
  const LeaderboardTable({super.key, required this.rows, this.limit});

  final List<LeaderboardRow> rows;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox(
        height: 140,
        child: EmptyState(title: 'No calls yet in this period', icon: Icons.leaderboard_outlined),
      );
    }
    final theme = Theme.of(context);
    final shown = limit == null ? rows : rows.take(limit!).toList();
    final header = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget cell(String text, {TextStyle? style, int flex = 2, TextAlign align = TextAlign.right}) => Expanded(
      flex: flex,
      child: Text(text, style: style, textAlign: align, overflow: TextOverflow.ellipsis),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 32),
              cell('Salesperson', style: header, flex: 5, align: TextAlign.left),
              cell('Calls', style: header),
              cell('Conn.', style: header),
              cell('Duration', style: header, flex: 3),
              cell('Conv.', style: header),
            ],
          ),
        ),
        const Divider(),
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: i < 3
                      ? Icon(
                          Icons.emoji_events,
                          size: 18,
                          color: [const Color(0xFFE0A100), const Color(0xFF98A2B3), const Color(0xFFB7791F)][i],
                        )
                      : Text('${i + 1}', style: theme.textTheme.labelMedium),
                ),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shown[i].name, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
                      if (shown[i].teamName != null)
                        Text(
                          shown[i].teamName!,
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                cell('${shown[i].calls}', style: theme.textTheme.bodyMedium),
                cell('${shown[i].connected}', style: theme.textTheme.bodyMedium),
                cell(formatDuration(shown[i].durationSeconds), style: theme.textTheme.bodyMedium, flex: 3),
                cell(
                  '${shown[i].conversions}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
