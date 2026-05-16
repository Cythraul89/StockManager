import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/chart_range.dart';
import '../../../core/models/exchange_rate.dart';
import '../../../core/models/price_point.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/decimal_math.dart';
import '../../settings/settings_provider.dart';
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
  bool _showConverted = false;

  @override
  Widget build(BuildContext context) {
    final historyAsync =
        ref.watch(priceHistoryProvider((widget.stockId, _range)));
    final settings = ref.watch(settingsStreamProvider).value;
    final rates = ref.watch(exchangeRatesProvider).value ?? [];

    final preferredCurrency = settings?.preferredCurrency;
    final nativeCurrency = historyAsync.value?.firstOrNull?.currency;

    ExchangeRate? convRate;
    if (preferredCurrency != null &&
        nativeCurrency != null &&
        nativeCurrency != preferredCurrency) {
      convRate = ExchangeRate.find(rates, nativeCurrency, preferredCurrency);
    }
    final canConvert = convRate != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(
              context,
              historyAsync.value,
              canConvert: canConvert,
              nativeCurrency: nativeCurrency,
              preferredCurrency: preferredCurrency,
            ),
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
                  : _buildChart(
                      context,
                      points,
                      convRate: _showConverted ? convRate : null,
                      preferredCurrency: preferredCurrency,
                    ),
            ),
            const SizedBox(height: 8),
            _buildRangeSelector(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    List<PricePoint>? points, {
    required bool canConvert,
    String? nativeCurrency,
    String? preferredCurrency,
  }) {
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
        const Spacer(),
        if (canConvert)
          _buildCurrencyToggle(context, nativeCurrency!, preferredCurrency!),
      ],
    );
  }

  Widget _buildCurrencyToggle(
      BuildContext context, String native, String preferred) {
    final theme = Theme.of(context);

    Widget pill(String code, bool selected) => GestureDetector(
          onTap: () => setState(() => _showConverted = code == preferred),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: selected
                ? BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  )
                : null,
            child: Text(
              code,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill(native, !_showConverted),
        pill(preferred, _showConverted),
      ],
    );
  }

  Widget _buildChart(
    BuildContext context,
    List<PricePoint> points, {
    ExchangeRate? convRate,
    String? preferredCurrency,
  }) {
    final theme = Theme.of(context);

    List<PricePoint> displayPoints;
    if (convRate != null && preferredCurrency != null) {
      // Capture as non-nullable locals so the closure doesn't need null checks.
      final rate = convRate;
      final toCurrency = preferredCurrency;
      displayPoints = points
          .map((p) => PricePoint(
                date: p.date,
                price: rate.convert(p.price),
                currency: toCurrency,
              ))
          .toList();
    } else {
      displayPoints = points;
    }

    final displayCurrency = displayPoints.first.currency;
    final first = displayPoints.first.price;
    final last = displayPoints.last.price;
    final isPositive = last >= first;
    final lineColor =
        isPositive ? Colors.green.shade500 : theme.colorScheme.error;

    // toDouble() is intentional — used only for pixel positioning in the chart,
    // not for any monetary arithmetic.
    final spots = <FlSpot>[];
    for (var i = 0; i < displayPoints.length; i++) {
      spots.add(FlSpot(i.toDouble(), displayPoints[i].price.toDouble()));
    }

    final minY = displayPoints
        .map((p) => p.price.toDouble())
        .reduce((a, b) => a < b ? a : b);
    final maxY = displayPoints
        .map((p) => p.price.toDouble())
        .reduce((a, b) => a > b ? a : b);
    final rawRange = maxY - minY;
    final yPadding = rawRange > 0 ? rawRange * 0.1 : maxY * 0.05;
    final chartMinY = minY - yPadding;
    final chartMaxY = maxY + yPadding;
    final yRange = chartMaxY - chartMinY;

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: chartMinY,
          maxY: chartMaxY,
          clipData: const FlClipData.all(),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 68,
                interval: yRange > 0 ? yRange / 4 : 1,
                getTitlesWidget: (value, meta) {
                  if (!value.isFinite) return const SizedBox.shrink();
                  Decimal price;
                  try {
                    price = Decimal.parse(value.toStringAsFixed(6));
                  } catch (_) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      CurrencyFormatter.compact(price, displayCurrency),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  );
                },
              ),
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
                interval: _labelInterval(displayPoints.length),
                getTitlesWidget: (value, meta) {
                  // fl_chart calls this for every spot; only render at the
                  // min/max markers and skip everything in between to avoid
                  // crowded labels.  The SideTitles.interval controls which
                  // values are passed, but we guard against edge values too.
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  final idx = value.round();
                  if (idx < 0 || idx >= displayPoints.length) {
                    return const SizedBox.shrink();
                  }
                  final label = _dateLabel(displayPoints[idx].date);
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
                if (idx < 0 || idx >= displayPoints.length) return null;
                final p = displayPoints[idx];
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
