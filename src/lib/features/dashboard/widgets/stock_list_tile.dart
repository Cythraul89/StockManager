import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/chart_range.dart';
import '../../../core/models/price_point.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/decimal_math.dart';
import '../../settings/settings_provider.dart';
import '../../stocks/stocks_provider.dart';
import '../dashboard_provider.dart';

class StockListTile extends ConsumerWidget {
  const StockListTile({super.key, required this.item});

  final StockSummaryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final noPrice = !item.hasPrice;
    final pnlColor = noPrice || item.unrealisedPnlPct.isNegative
        ? (noPrice ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.error)
        : Colors.green;

    // Analyst data: show badge when available; load silently in background.
    final analystAsync = ref.watch(analystDataProvider(item.stock.id));
    final recKey = analystAsync.value?.recommendationKey;
    final (recLabel, recColor) = _recommendationStyle(recKey);

    final sparklineRange = ref.watch(settingsStreamProvider).value?.sparklineRange
        ?? ChartRange.oneMonth;
    final sparkAsync =
        ref.watch(priceHistoryProvider((item.stock.id, sparklineRange)));
    final sparkPoints = sparkAsync.value;

    return ListTile(
      onTap: () => context.push('/stocks/${item.stock.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(item.stock.symbol,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    if (recLabel != null) ...[
                      const SizedBox(width: 6),
                      _recBadge(context, recLabel, recColor),
                    ],
                  ],
                ),
                Text(item.stock.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (sparkPoints != null && sparkPoints.length >= 2) ...[
            _buildSparkline(context, sparkPoints),
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                noPrice
                    ? '—'
                    : CurrencyFormatter.format(
                        item.currentValue, item.preferredCurrency),
                style: theme.textTheme.bodyMedium,
              ),
              Row(
                children: [
                  if (item.missingRate)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.currency_exchange,
                          size: 12,
                          color: theme.colorScheme.error),
                    ),
                  if (item.isStale && !noPrice)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.warning_amber_rounded,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  Text(
                    noPrice
                        ? 'No price data'
                        : CurrencyFormatter.formatPercent(
                            item.unrealisedPnlPct),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: pnlColor),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      subtitle: Text(
        noPrice
            ? '${item.sharesHeld.toStringAsFixed(4)} shares'
            : _priceSubtitle(item),
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _recBadge(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.5),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
      ),
    );
  }

  (String?, Color) _recommendationStyle(String? key) {
    return switch (key?.toLowerCase()) {
      'strongbuy' || 'strong_buy' => ('Str.Buy', Colors.green.shade800),
      'buy' => ('Buy', Colors.green.shade600),
      'hold' => ('Hold', Colors.amber.shade700),
      'underperform' => ('Undprf.', Colors.orange.shade700),
      'sell' || 'strongsell' || 'strong_sell' => ('Sell', Colors.red),
      _ => (null, Colors.transparent),
    };
  }

  String _priceSubtitle(StockSummaryItem item) {
    final shares = '${item.sharesHeld.toStringAsFixed(4)} shares @ ';
    final converted =
        CurrencyFormatter.format(item.currentPrice, item.stock.currency);
    if (item.quoteCurrency == item.stock.currency) return '$shares$converted';
    final raw =
        CurrencyFormatter.format(item.rawQuotePrice, item.quoteCurrency);
    return '$shares$converted ($raw)';
  }

  Widget _buildSparkline(BuildContext context, List<PricePoint> points) {
    final isUp = points.last.price >= points.first.price;
    final color =
        isUp ? Colors.green.shade600 : Theme.of(context).colorScheme.error;
    final spots = List.generate(
      points.length,
      (i) => FlSpot(i.toDouble(), points[i].price.toDouble()),
    );
    final minY = spots.fold(spots.first.y, (m, s) => s.y < m ? s.y : m);
    final maxY = spots.fold(spots.first.y, (m, s) => s.y > m ? s.y : m);
    final pad = (maxY - minY) > 0 ? (maxY - minY) * 0.1 : maxY * 0.05;

    return SizedBox(
      width: 72,
      height: 36,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.15),
              ),
            ),
          ],
          minY: minY - pad,
          maxY: maxY + pad,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
        ),
        duration: Duration.zero,
      ),
    );
  }
}
