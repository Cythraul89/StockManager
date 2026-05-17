import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/chart_range.dart';
import '../../../core/models/exchange_rate.dart';
import '../../../core/models/price_point.dart';
import '../../../core/models/transaction.dart';
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
    final transactions =
        ref.watch(transactionsByStockProvider(widget.stockId)).value ?? [];
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
                  : KeyedSubtree(
                      // Force a full chart rebuild on range change so fl_chart
                      // doesn't try to animate between incompatible datasets.
                      key: ValueKey(_range),
                      child: _buildChart(
                        context,
                        points,
                        transactions: transactions,
                        convRate: _showConverted ? convRate : null,
                        preferredCurrency: preferredCurrency,
                      ),
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
    required List<StockTransaction> transactions,
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

    // ── Transaction overlay dots ──────────────────────────────────────────────
    // Each transaction is placed at the nearest chart data point by date.
    // Separate lists for buys and sells so they get distinct bar indices and
    // can be identified in the tooltip callback.
    final chartStart = displayPoints.first.date;
    final chartEnd = displayPoints.last.date;

    final buySpots = <FlSpot>[];
    final buyTxs = <StockTransaction>[];
    final sellSpots = <FlSpot>[];
    final sellTxs = <StockTransaction>[];

    for (final tx in transactions) {
      if (tx.executedAt.isBefore(chartStart) ||
          tx.executedAt.isAfter(chartEnd)) {
        continue;
      }
      final idx = _nearestPointIndex(displayPoints, tx.executedAt);
      final spot =
          FlSpot(idx.toDouble(), displayPoints[idx].price.toDouble());
      if (tx.type == TransactionType.buy) {
        buySpots.add(spot);
        buyTxs.add(tx);
      } else {
        sellSpots.add(spot);
        sellTxs.add(tx);
      }
    }

    // Build lineBarsData with tracked bar indices so the tooltip can identify
    // which bar a touch belongs to regardless of which overlays are present.
    final List<LineChartBarData> lineBarsData = [];
    const int priceBarIdx = 0;
    lineBarsData.add(LineChartBarData(
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
    ));

    int? buyBarIdx;
    int? sellBarIdx;

    if (buySpots.isNotEmpty) {
      buyBarIdx = lineBarsData.length;
      lineBarsData.add(LineChartBarData(
        spots: buySpots,
        barWidth: 0,
        color: Colors.transparent,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, pct, barData, idx) => FlDotCirclePainter(
            radius: 5,
            color: Colors.green.shade600,
            strokeWidth: 1.5,
            strokeColor: theme.colorScheme.surface,
          ),
        ),
      ));
    }

    if (sellSpots.isNotEmpty) {
      sellBarIdx = lineBarsData.length;
      lineBarsData.add(LineChartBarData(
        spots: sellSpots,
        barWidth: 0,
        color: Colors.transparent,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, pct, barData, idx) => FlDotCirclePainter(
            radius: 5,
            color: theme.colorScheme.error,
            strokeWidth: 1.5,
            strokeColor: theme.colorScheme.surface,
          ),
        ),
      ));
    }

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
              getTooltipItems: (touchedSpots) {
                // Find the x position the price line resolved to — used to
                // suppress transaction tooltips that are too far from the
                // actual touch position (fl_chart always includes the nearest
                // spot from every bar, even when far away).
                double? priceX;
                for (final s in touchedSpots) {
                  if (s.barIndex == priceBarIdx) {
                    priceX = s.x;
                    break;
                  }
                }

                return touchedSpots.map((s) {
                  if (s.barIndex == priceBarIdx) {
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
                  }

                  // Suppress transaction tooltip when it is more than 2 data
                  // points from the touched price position.
                  if (priceX == null || (s.x - priceX).abs() > 2) {
                    return null;
                  }

                  final List<StockTransaction>? txList;
                  final bool isBuy;
                  if (s.barIndex == buyBarIdx) {
                    txList = buyTxs;
                    isBuy = true;
                  } else if (s.barIndex == sellBarIdx) {
                    txList = sellTxs;
                    isBuy = false;
                  } else {
                    return null;
                  }

                  if (s.spotIndex >= txList.length) return null;
                  final tx = txList[s.spotIndex];
                  final label = isBuy ? 'BUY' : 'SELL';
                  final color = isBuy
                      ? Colors.green.shade600
                      : theme.colorScheme.error;
                  return LineTooltipItem(
                    '$label  ${tx.shares.toStringFixed(4)} shares\n',
                    TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    children: [
                      TextSpan(
                        text:
                            '@ ${CurrencyFormatter.format(tx.pricePerShare, tx.currency)}',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.normal,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: lineBarsData,
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

  int _nearestPointIndex(List<PricePoint> points, DateTime date) {
    var best = 0;
    var bestDiff = (points[0].date.millisecondsSinceEpoch -
            date.millisecondsSinceEpoch)
        .abs();
    for (var i = 1; i < points.length; i++) {
      final diff =
          (points[i].date.millisecondsSinceEpoch - date.millisecondsSinceEpoch)
              .abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }
}
