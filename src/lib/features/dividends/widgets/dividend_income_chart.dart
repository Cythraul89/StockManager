import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/dividend.dart';
import '../../../core/models/exchange_rate.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../settings/settings_provider.dart';
import '../../stocks/stocks_provider.dart';

enum _Period { monthly, yearly }

class DividendIncomeChart extends ConsumerStatefulWidget {
  const DividendIncomeChart({super.key});

  @override
  ConsumerState<DividendIncomeChart> createState() =>
      _DividendIncomeChartState();
}

class _DividendIncomeChartState extends ConsumerState<DividendIncomeChart> {
  _Period _period = _Period.monthly;

  @override
  Widget build(BuildContext context) {
    final dividendsAsync = ref.watch(allDividendsProvider);
    final rates = ref.watch(exchangeRatesProvider).value ?? [];
    final preferred =
        ref.watch(settingsStreamProvider).value?.preferredCurrency ?? 'USD';

    return dividendsAsync.when(
      loading: () => const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (dividends) {
        final paid = dividends
            .where((d) =>
                d.type == DividendType.paid &&
                d.confirmed &&
                d.netAmount > Decimal.zero)
            .toList();

        if (paid.isEmpty) return const SizedBox.shrink();

        final buckets = _buildBuckets(paid, rates, preferred);
        if (buckets.isEmpty) return const SizedBox.shrink();

        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Dividend Income',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    _buildPeriodToggle(context),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: _buildBarChart(context, buckets, preferred),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // Groups paid+confirmed dividends by period key ("2025-01" or "2025"),
  // converting each to the preferred currency. Sorted chronologically.
  Map<String, Decimal> _buildBuckets(
    List<Dividend> paid,
    List<ExchangeRate> rates,
    String preferred,
  ) {
    final map = <String, Decimal>{};

    for (final d in paid) {
      final Decimal amount;
      if (d.currency == preferred) {
        amount = d.netAmount;
      } else {
        final rate = ExchangeRate.find(rates, d.currency, preferred);
        // Skip dividends whose currency cannot be converted — including them
        // with the raw amount would silently mix currencies in the totals.
        if (rate == null) continue;
        amount = rate.convert(d.netAmount);
      }

      final key = _period == _Period.monthly
          ? '${d.date.year}-${d.date.month.toString().padLeft(2, '0')}'
          : d.date.year.toString();

      map[key] = (map[key] ?? Decimal.zero) + amount;
    }

    final sorted = Map.fromEntries(
      map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return sorted;
  }

  Widget _buildBarChart(
    BuildContext context,
    Map<String, Decimal> buckets,
    String currency,
  ) {
    final theme = Theme.of(context);
    final keys = buckets.keys.toList();
    final values = buckets.values.toList();
    final maxVal =
        values.fold(Decimal.zero, (m, v) => v > m ? v : m).toDouble();

    // Bar width shrinks as count grows so all bars fit comfortably.
    final barWidth = keys.length <= 12
        ? 14.0
        : keys.length <= 24
            ? 9.0
            : 6.0;

    return BarChart(
      BarChartData(
        maxY: maxVal * 1.18,
        barGroups: List.generate(
          keys.length,
          (i) => BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: values[i].toDouble(),
                color: theme.colorScheme.primary,
                width: barWidth,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ],
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxVal > 0 ? maxVal / 4 : 1,
          getDrawingHorizontalLine: (_) => FlLine(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 0.5,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              interval: maxVal > 0 ? maxVal / 4 : 1,
              getTitlesWidget: (value, meta) {
                if (!value.isFinite || value == meta.min) {
                  return const SizedBox.shrink();
                }
                Decimal dec;
                try {
                  dec = Decimal.parse(value.toStringAsFixed(4));
                } catch (_) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    CurrencyFormatter.compact(dec, currency),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= keys.length) return const SizedBox.shrink();
                final label = _bottomLabel(keys, i);
                if (label == null) return const SizedBox.shrink();
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
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) =>
                theme.colorScheme.surfaceContainerHighest,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final key = keys[group.x];
              final amount = values[group.x];
              final label = _period == _Period.monthly
                  ? _fullMonthLabel(key)
                  : key;
              return BarTooltipItem(
                '$label\n',
                TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                children: [
                  TextSpan(
                    text: CurrencyFormatter.format(amount, currency),
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      duration: const Duration(milliseconds: 200),
    );
  }

  // Returns an x-axis label for the bar at [index] in [keys], or null to skip.
  String? _bottomLabel(List<String> keys, int index) {
    if (_period == _Period.yearly) return keys[index];

    final total = keys.length;
    // Skip interval: show every bar up to 12; every 3rd up to 24; every 6th after.
    final skip = total <= 12 ? 1 : total <= 24 ? 3 : 6;
    if (index % skip != 0) return null;

    final parts = keys[index].split('-');
    if (parts.length < 2) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return null;
    final dt = DateTime(year, month);

    return total <= 12
        ? DateFormat('MMM').format(dt)
        : DateFormat("MMM ''yy").format(dt);
  }

  String _fullMonthLabel(String key) {
    final parts = key.split('-');
    if (parts.length < 2) return key;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return key;
    return DateFormat('MMM yyyy').format(DateTime(year, month));
  }

  Widget _buildPeriodToggle(BuildContext context) {
    final theme = Theme.of(context);

    Widget btn(String label, _Period p) => GestureDetector(
          onTap: () => setState(() => _period = p),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: _period == p
                ? BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: _period == p
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight:
                    _period == p ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn('Monthly', _Period.monthly),
        btn('Yearly', _Period.yearly),
      ],
    );
  }
}
