import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/chart_range.dart';
import '../../../core/models/price_point.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/decimal_math.dart';
import '../stocks_provider.dart';

class StockPriceChart extends ConsumerStatefulWidget {
  const StockPriceChart({
    super.key,
    required this.stockId,
  });

  final String stockId;

  @override
  ConsumerState<StockPriceChart> createState() => _StockPriceChartState();
}

class _StockPriceChartState extends ConsumerState<StockPriceChart> {
  ChartRange _range = ChartRange.oneMonth;

  @override
  Widget build(BuildContext context) {
    final historyAsync =
        ref.watch(priceHistoryProvider((widget.stockId, _range)));

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, historyAsync.value),
            const SizedBox(height: 12),
            historyAsync.when(
              loading: () => const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const SizedBox(
                height: 160,
                child: Center(child: Text('Could not load price history')),
              ),
              data: (points) => points.isEmpty
                  ? const SizedBox(
                      height: 160,
                      child: Center(child: Text('No data available')),
                    )
                  : _buildChart(context, points),
            ),
            const SizedBox(height: 8),
            _buildRangeSelector(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, List<PricePoint>? points) {
    final theme = Theme.of(context);
    String? changeLabel;
    Color? changeColor;
    if (points != null && points.length >= 2) {
      final first = points.first.price;
      final last = points.last.price;
      if (first > Decimal.zero) {
        final pct = last.percentChangeFrom(first);
        final sign = pct.isNegative ? '' : '+';
        changeLabel = '$sign${pct.toStringFixed(2)}%';
        changeColor = pct.isNegative
            ? theme.colorScheme.error
            : Colors.green.shade600;
      }
    }

    return Row(
      children: [
        Text('Price History', style: theme.textTheme.titleMedium),
        if (changeLabel != null) ...[
          const SizedBox(width: 8),
          Text(
            changeLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: changeColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildChart(BuildContext context, List<PricePoint> points) {
    final theme = Theme.of(context);
    final currency = points.first.currency;
    final first = points.first.price;
    final last = points.last.price;
    final isPositive = last >= first;
    final lineColor =
        isPositive ? Colors.green.shade500 : theme.colorScheme.error;

    // toDouble() is intentional — used only for pixel positioning in the chart,
    // not for any monetary arithmetic.
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      spots.add(FlSpot(i.toDouble(), points[i].price.toDouble()));
    }

    final minY = points.map((p) => p.price.toDouble()).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((p) => p.price.toDouble()).reduce((a, b) => a > b ? a : b);
    final yPadding = (maxY - minY) * 0.1;

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: minY - yPadding,
          maxY: maxY + yPadding,
          clipData: const FlClipData.all(),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: _labelInterval(points.length),
                getTitlesWidget: (value, meta) {
                  // fl_chart calls this for every spot; only render at the
                  // min/max markers and skip everything in between to avoid
                  // crowded labels.  The SideTitles.interval controls which
                  // values are passed, but we guard against edge values too.
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  final idx = value.round();
                  if (idx < 0 || idx >= points.length) {
                    return const SizedBox.shrink();
                  }
                  final label = _dateLabel(points[idx].date);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) =>
                  theme.colorScheme.surfaceContainerHighest,
              getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                final idx = s.spotIndex;
                if (idx < 0 || idx >= points.length) return null;
                final p = points[idx];
                return LineTooltipItem(
                  '${CurrencyFormatter.format(p.price, p.currency)}\n',
                  TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  children: [
                    TextSpan(
                      text: _tooltipDate(p.date),
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.normal,
                        fontSize: 11,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.2,
              color: lineColor,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    lineColor.withValues(alpha: 0.25),
                    lineColor.withValues(alpha: 0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 250),
      ),
    );
  }

  Widget _buildRangeSelector(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: ChartRange.values.map((r) {
        final selected = r == _range;
        return GestureDetector(
          onTap: () => setState(() => _range = r),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: selected
                ? BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Text(
              r.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  double _labelInterval(int count) {
    if (count <= 10) return 1;
    if (count <= 30) return (count / 4).ceilToDouble();
    if (count <= 100) return (count / 5).ceilToDouble();
    return (count / 6).ceilToDouble();
  }

  String _dateLabel(DateTime date) {
    return switch (_range) {
      ChartRange.oneDay => DateFormat('HH:mm').format(date.toLocal()),
      ChartRange.oneWeek ||
      ChartRange.oneMonth =>
        DateFormat('d MMM').format(date.toLocal()),
      ChartRange.sixMonths ||
      ChartRange.oneYear =>
        DateFormat('MMM').format(date.toLocal()),
      ChartRange.fiveYears ||
      ChartRange.max =>
        DateFormat('yyyy').format(date.toLocal()),
    };
  }

  String _tooltipDate(DateTime date) {
    return switch (_range) {
      ChartRange.oneDay => DateFormat('HH:mm').format(date.toLocal()),
      _ => DateFormat('d MMM yyyy').format(date.toLocal()),
    };
  }
}
