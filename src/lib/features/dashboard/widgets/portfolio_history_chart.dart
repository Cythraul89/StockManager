import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';
import '../dashboard_provider.dart';

class PortfolioHistoryChart extends StatefulWidget {
  const PortfolioHistoryChart({super.key, required this.points});

  final List<PortfolioHistoryPoint> points;

  @override
  State<PortfolioHistoryChart> createState() => _PortfolioHistoryChartState();
}

class _PortfolioHistoryChartState extends State<PortfolioHistoryChart> {
  static const _colorInvested = Color(0xFF4C7CE5);
  static const _colorGain = Color(0xFF2DB87D);
  static const _colorLoss = Color(0xFFE55C5C);
  static const _colorDividends = Color(0xFFE5A23C);

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final currency = widget.points.first.currency;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Portfolio History', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: _buildChart(context, currency),
            ),
            const SizedBox(height: 12),
            _buildLegend(context),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(BuildContext context, String currency) {
    final theme = Theme.of(context);
    final points = widget.points;

    // Determine Y-axis range across all bars.
    double maxY = 0;
    double minY = 0;
    for (final p in points) {
      final top = p.investedCapital.toDouble();
      final mid = p.realisedPnl.toDouble();
      final bot = p.dividends.toDouble();
      if (top > maxY) maxY = top;
      if (mid > maxY) maxY = mid;
      if (bot > maxY) maxY = bot;
      if (mid < minY) minY = mid;
    }
    maxY *= 1.18;
    minY = minY < 0 ? minY * 1.18 : 0;

    if (maxY == 0) maxY = 1;

    final barWidth = points.length <= 5
        ? 14.0
        : points.length <= 10
            ? 10.0
            : 7.0;

    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: minY,
        barGroups: List.generate(points.length, (i) {
          final p = points[i];
          final gainColor =
              p.realisedPnl >= Decimal.zero ? _colorGain : _colorLoss;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: p.investedCapital.toDouble(),
                color: _colorInvested,
                width: barWidth,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
              BarChartRodData(
                toY: p.realisedPnl.toDouble(),
                color: gainColor,
                width: barWidth,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
              BarChartRodData(
                toY: p.dividends.toDouble(),
                color: _colorDividends,
                width: barWidth,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ],
          );
        }),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY > 0 ? maxY / 4 : 1,
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
              interval: maxY > 0 ? maxY / 4 : 1,
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
                if (i < 0 || i >= points.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    points[i].year.toString(),
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
              final p = points[group.x];
              final gainColor =
                  p.realisedPnl >= Decimal.zero ? _colorGain : _colorLoss;
              const labels = ['Invested', 'Realised P&L', 'Dividends'];
              final values = [p.investedCapital, p.realisedPnl, p.dividends];
              final colors = [_colorInvested, gainColor, _colorDividends];
              final extra = rodIndex == 0 && p.totalValue != null
                  ? '\nValue: ${CurrencyFormatter.compact(p.totalValue!, currency)}'
                  : '';
              return BarTooltipItem(
                '${p.year}\n',
                TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                children: [
                  TextSpan(
                    text:
                        '${labels[rodIndex]}: ${CurrencyFormatter.compact(values[rodIndex], currency)}$extra',
                    style: TextStyle(
                      color: colors[rodIndex],
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
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

  Widget _buildLegend(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _legendItem(theme, _colorInvested, 'Invested'),
        _legendItem(theme, _colorGain, 'Realised P&L'),
        _legendItem(theme, _colorDividends, 'Dividends'),
      ],
    );
  }

  Widget _legendItem(ThemeData theme, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
