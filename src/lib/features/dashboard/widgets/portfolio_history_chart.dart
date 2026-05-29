import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';
import '../dashboard_provider.dart';

const _kForecastYears = 5;

class PortfolioHistoryChart extends StatefulWidget {
  const PortfolioHistoryChart({super.key, required this.points});

  final List<PortfolioHistoryPoint> points;

  @override
  State<PortfolioHistoryChart> createState() => _PortfolioHistoryChartState();
}

class _PortfolioHistoryChartState extends State<PortfolioHistoryChart> {
  bool _showForecast = false;

  static const _colorInvested = Color(0xFF4C7CE5);
  static const _colorGain = Color(0xFF2DB87D);
  static const _colorLoss = Color(0xFFE55C5C);
  static const _colorDividends = Color(0xFFE5A23C);

  // Linear extrapolation of [_kForecastYears] future data points from the
  // overall trend: slope = (last − first) / yearSpan for each metric.
  List<PortfolioHistoryPoint> _forecast(List<PortfolioHistoryPoint> historical) {
    if (historical.length < 2) return [];
    final first = historical.first;
    final last = historical.last;
    final yearSpan = last.year - first.year;
    if (yearSpan == 0) return [];

    Decimal slope(Decimal end, Decimal start) =>
        ((end - start).toRational() / Decimal.fromInt(yearSpan).toRational())
            .toDecimal(scaleOnInfinitePrecision: 10);

    Decimal project(Decimal base, Decimal s, int steps) =>
        base +
        (s.toRational() * Decimal.fromInt(steps).toRational())
            .toDecimal(scaleOnInfinitePrecision: 10);

    final sInvested = slope(last.investedCapital, first.investedCapital);
    final sPnl = slope(last.realisedPnl, first.realisedPnl);
    final sDivs = slope(last.dividends, first.dividends);

    return List.generate(_kForecastYears, (i) {
      final steps = i + 1;
      final projInvested = project(last.investedCapital, sInvested, steps);
      return PortfolioHistoryPoint(
        year: last.year + steps,
        // Cost basis cannot go negative.
        investedCapital:
            projInvested < Decimal.zero ? Decimal.zero : projInvested,
        realisedPnl: project(last.realisedPnl, sPnl, steps),
        dividends: project(last.dividends, sDivs, steps),
        currency: last.currency,
        isProjected: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final currency = widget.points.first.currency;
    final canForecast = widget.points.length >= 2;
    final forecast =
        _showForecast && canForecast ? _forecast(widget.points) : <PortfolioHistoryPoint>[];
    final allPoints = [...widget.points, ...forecast];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Portfolio History', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (canForecast) _buildForecastToggle(context),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: _buildChart(context, allPoints, currency),
            ),
            const SizedBox(height: 12),
            _buildLegend(context),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildForecastToggle(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => setState(() => _showForecast = !_showForecast),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: _showForecast
            ? BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        child: Text(
          'Forecast',
          style: theme.textTheme.labelSmall?.copyWith(
            color: _showForecast
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
            fontWeight:
                _showForecast ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildChart(
    BuildContext context,
    List<PortfolioHistoryPoint> points,
    String currency,
  ) {
    final theme = Theme.of(context);

    double maxY = 0;
    double minY = 0;
    for (final p in points) {
      final invested = p.investedCapital.toDouble();
      final pnl = p.realisedPnl.toDouble();
      final divs = p.dividends.toDouble();
      if (invested > maxY) maxY = invested;
      if (pnl > maxY) maxY = pnl;
      if (divs > maxY) maxY = divs;
      if (pnl < minY) minY = pnl;
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
          final opacity = p.isProjected ? 0.35 : 1.0;
          final gainColor =
              p.realisedPnl >= Decimal.zero ? _colorGain : _colorLoss;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: p.investedCapital.toDouble(),
                color: _colorInvested.withValues(alpha: opacity),
                width: barWidth,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
              BarChartRodData(
                toY: p.realisedPnl.toDouble(),
                color: gainColor.withValues(alpha: opacity),
                width: barWidth,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
              BarChartRodData(
                toY: p.dividends.toDouble(),
                color: _colorDividends.withValues(alpha: opacity),
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
                final p = points[i];
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    p.year.toString(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: p.isProjected
                          ? theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5)
                          : theme.colorScheme.onSurfaceVariant,
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
              final prefix = p.isProjected ? '~' : '';
              final extra = rodIndex == 0 && p.totalValue != null
                  ? '\nValue: ${CurrencyFormatter.compact(p.totalValue!, currency)}'
                  : '';
              return BarTooltipItem(
                '${p.year}${p.isProjected ? ' (forecast)' : ''}\n',
                TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                children: [
                  TextSpan(
                    text:
                        '${labels[rodIndex]}: $prefix${CurrencyFormatter.compact(values[rodIndex], currency)}$extra',
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
      duration: const Duration(milliseconds: 250),
    );
  }

  Widget _buildLegend(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _legendDot(theme, _colorInvested, 'Invested'),
        _legendDot(theme, _colorGain, 'Realised P&L'),
        _legendDot(theme, _colorDividends, 'Dividends'),
        if (_showForecast)
          _legendDot(
            theme,
            theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            'Forecast (trend)',
          ),
      ],
    );
  }

  Widget _legendDot(ThemeData theme, Color color, String label) {
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
