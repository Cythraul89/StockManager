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

  static const _colorInvested   = Color(0xFF4C7CE5);
  static const _colorUnrealised = Color(0xFF2DB87D);
  static const _colorRealised   = Color(0xFF1A8A57);
  static const _colorDividends  = Color(0xFFE5A23C);

  // Unrealised P&L is only known for the current year (totalValue != null).
  static Decimal _unrealisedFor(PortfolioHistoryPoint p) =>
      p.totalValue != null ? p.totalValue! - p.investedCapital : Decimal.zero;

  List<PortfolioHistoryPoint> _forecast(List<PortfolioHistoryPoint> historical) {
    if (historical.length < 2) return [];
    final first    = historical.first;
    final last     = historical.last;
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
    final sPnl      = slope(last.realisedPnl,     first.realisedPnl);
    final sDivs     = slope(last.dividends,        first.dividends);

    return List.generate(_kForecastYears, (i) {
      final steps        = i + 1;
      final projInvested = project(last.investedCapital, sInvested, steps);
      return PortfolioHistoryPoint(
        year:            last.year + steps,
        investedCapital: projInvested < Decimal.zero ? Decimal.zero : projInvested,
        realisedPnl:     project(last.realisedPnl, sPnl,  steps),
        dividends:       project(last.dividends,   sDivs, steps),
        currency:        last.currency,
        isProjected:     true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) return const SizedBox.shrink();

    final theme       = Theme.of(context);
    final currency    = widget.points.first.currency;
    final canForecast = widget.points.length >= 2;
    final forecast    = _showForecast && canForecast
        ? _forecast(widget.points)
        : <PortfolioHistoryPoint>[];
    final allPoints   = [...widget.points, ...forecast];

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
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: _buildMainChart(context, allPoints, currency),
            ),
            const SizedBox(height: 8),
            _buildMainLegend(context),
            const SizedBox(height: 16),
            Text(
              'Dividends (cumulative)',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 90,
              child: _buildDividendsChart(context, allPoints, currency),
            ),
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
            fontWeight: _showForecast ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildMainChart(
    BuildContext context,
    List<PortfolioHistoryPoint> points,
    String currency,
  ) {
    final theme = Theme.of(context);

    // Three series at cumulative Y values, drawn in reverse-cover order:
    //   [0] total (invested+unrealised+realised) — drawn first (bottom render layer)
    //   [1] invested+unrealised                  — drawn second
    //   [2] invested                             — drawn last (top render layer)
    // Each belowBarData fills from 0 to its line. Because later series paint on
    // top of earlier ones, the final visual zones are:
    //   0 → invested          : blue  (series [2] fill covers everything below)
    //   invested → +unrealised: teal  (series [1] fill covers, series [2] doesn't reach)
    //   +unrealised → total   : green (only series [0] fill remains visible here)
    final spots1 = <FlSpot>[];  // invested
    final spots2 = <FlSpot>[];  // invested + unrealised
    final spots3 = <FlSpot>[];  // total

    double minY = 0;
    double maxY = 0;

    for (int i = 0; i < points.length; i++) {
      final p      = points[i];
      final unreal = _unrealisedFor(p).toDouble();
      final y1     = p.investedCapital.toDouble();
      final y2     = y1 + unreal;
      final y3     = y2 + p.realisedPnl.toDouble();

      spots1.add(FlSpot(i.toDouble(), y1));
      spots2.add(FlSpot(i.toDouble(), y2));
      spots3.add(FlSpot(i.toDouble(), y3));

      if (y1 > maxY) maxY = y1;
      if (y2 > maxY) maxY = y2;
      if (y3 > maxY) maxY = y3;
      if (y3 < minY) minY = y3;
      if (y2 < minY) minY = y2;
    }

    maxY *= 1.18;
    if (maxY == 0) maxY = 1;
    minY = minY < 0 ? minY * 1.18 : 0;

    final interval  = maxY > 0 ? maxY / 4 : 1.0;
    final xInterval = points.length <= 7 ? 1.0 : 2.0;
    final gridColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.5);

    LineChartBarData makeLine(List<FlSpot> spots, Color line, Color fill) =>
        LineChartBarData(
          spots:        spots,
          color:        line,
          barWidth:     2,
          isCurved:     false,
          dotData:      const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: fill),
        );

    return LineChart(
      LineChartData(
        minY:     minY,
        maxY:     maxY,
        clipData: const FlClipData.all(),
        lineBarsData: [
          makeLine(spots3, _colorRealised,   _colorRealised.withValues(alpha: 0.60)),
          makeLine(spots2, _colorUnrealised, _colorUnrealised.withValues(alpha: 0.65)),
          makeLine(spots1, _colorInvested,   _colorInvested.withValues(alpha: 0.70)),
        ],
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: gridColor, strokeWidth: 0.5),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles:   true,
              reservedSize: 60,
              interval:     interval,
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
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles:   true,
              reservedSize: 24,
              interval:     xInterval,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
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
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.surfaceContainerHighest,
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
              // Only one tooltip per touch (for the total line, barIndex 0).
              if (spot.barIndex != 0) return null;
              final i = spot.x.round();
              if (i < 0 || i >= points.length) return null;
              final p          = points[i];
              final unrealised = _unrealisedFor(p);
              final total      = p.investedCapital + unrealised + p.realisedPnl;

              final rows = <TextSpan>[
                TextSpan(
                  text: 'Invested: '
                      '${CurrencyFormatter.compact(p.investedCapital, currency)}',
                  style: const TextStyle(
                    color: _colorInvested, fontSize: 11, fontWeight: FontWeight.w500,
                  ),
                ),
                if (unrealised != Decimal.zero)
                  TextSpan(
                    text: '\nUnrealised: '
                        '${CurrencyFormatter.compact(unrealised, currency)}',
                    style: const TextStyle(
                      color: _colorUnrealised, fontSize: 11, fontWeight: FontWeight.w500,
                    ),
                  ),
                TextSpan(
                  text: '\nRealised: '
                      '${CurrencyFormatter.compact(p.realisedPnl, currency)}',
                  style: const TextStyle(
                    color: _colorRealised, fontSize: 11, fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: '\nTotal: ${CurrencyFormatter.compact(total, currency)}',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ];

              return LineTooltipItem(
                '${p.year}${p.isProjected ? ' (forecast)' : ''}\n',
                TextStyle(
                  color:      theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize:   12,
                ),
                children: rows,
              );
            }).toList(),
          ),
        ),
      ),
      duration: const Duration(milliseconds: 250),
    );
  }

  Widget _buildDividendsChart(
    BuildContext context,
    List<PortfolioHistoryPoint> points,
    String currency,
  ) {
    final theme = Theme.of(context);

    final spots = <FlSpot>[];
    double maxY = 0;
    for (int i = 0; i < points.length; i++) {
      final y = points[i].dividends.toDouble();
      spots.add(FlSpot(i.toDouble(), y));
      if (y > maxY) maxY = y;
    }
    maxY *= 1.3;
    if (maxY == 0) maxY = 1;

    final interval  = maxY / 2;
    final xInterval = points.length <= 7 ? 1.0 : 2.0;
    final gridColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.5);

    return LineChart(
      LineChartData(
        minY:     0,
        maxY:     maxY,
        clipData: const FlClipData.all(),
        lineBarsData: [
          LineChartBarData(
            spots:        spots,
            color:        _colorDividends,
            barWidth:     2,
            isCurved:     false,
            dotData:      const FlDotData(show: false),
            belowBarData: BarAreaData(
              show:  true,
              color: _colorDividends.withValues(alpha: 0.35),
            ),
          ),
        ],
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: gridColor, strokeWidth: 0.5),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles:   true,
              reservedSize: 60,
              interval:     interval,
              getTitlesWidget: (value, meta) {
                if (!value.isFinite || value == 0 || value == meta.min) {
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
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles:   true,
              reservedSize: 20,
              interval:     xInterval,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                final p = points[i];
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
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
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.surfaceContainerHighest,
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
              final i = spot.x.round();
              if (i < 0 || i >= points.length) return null;
              final p = points[i];
              return LineTooltipItem(
                '${p.year}${p.isProjected ? ' (forecast)' : ''}\n',
                TextStyle(
                  color:      theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize:   12,
                ),
                children: [
                  TextSpan(
                    text: 'Dividends: '
                        '${CurrencyFormatter.compact(p.dividends, currency)}',
                    style: const TextStyle(
                      color:      _colorDividends,
                      fontSize:   11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
      duration: const Duration(milliseconds: 250),
    );
  }

  Widget _buildMainLegend(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing:    16,
      runSpacing: 4,
      children: [
        _legendDot(theme, _colorInvested,   'Invested'),
        _legendDot(theme, _colorUnrealised, 'Unrealised P&L'),
        _legendDot(theme, _colorRealised,   'Realised P&L'),
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
          width:  10,
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
