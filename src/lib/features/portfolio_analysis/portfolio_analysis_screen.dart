import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/analyst_data.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/decimal_math.dart';
import '../dashboard/dashboard_provider.dart';

class PortfolioAnalysisScreen extends ConsumerWidget {
  const PortfolioAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buys = ref.watch(topBuysProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Top Buy Recommendations')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Based on analyst consensus, these are your most recommended '
            'holdings to add to.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (buys.isEmpty)
            _EmptyState(theme: theme)
          else ...[
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (int i = 0; i < buys.take(10).length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _BuyTile(
                      rank: i + 1,
                      item: buys[i].item,
                      analyst: buys[i].analyst,
                    ),
                  ],
                ],
              ),
            ),
            if (buys.length > 10) ...[
              const SizedBox(height: 8),
              Text(
                '${buys.length - 10} more buy-rated holdings not shown.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
          const SizedBox(height: 24),
          Text(
            'Analyst data is fetched from Yahoo Finance / Finnhub and may be '
            'delayed. This is not financial advice.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.analytics_outlined,
              size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            'No buy recommendations yet',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Analyst data is loaded in the background.\n'
            'Visit each stock\'s detail screen to trigger a fetch,\n'
            'or wait a moment for data to arrive.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BuyTile extends StatelessWidget {
  const _BuyTile({
    required this.rank,
    required this.item,
    required this.analyst,
  });

  final int rank;
  final StockSummaryItem item;
  final AnalystData analyst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStrongBuy =
        analyst.recommendationKey?.toLowerCase() == 'strong_buy';
    final recColor =
        isStrongBuy ? Colors.green.shade800 : Colors.green.shade600;
    final recLabel = isStrongBuy ? 'Strong Buy' : 'Buy';

    final upside = analystUpside(item, analyst);
    final sign = (upside?.isNegative ?? false) ? '' : '+';
    final upsideStr =
        upside != null ? '$sign${upside.toStringFixed(1)}% to target' : null;

    return ListTile(
      onTap: () => context.push('/stocks/${item.stock.id}'),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: recColor.withValues(alpha: 0.12),
        child: Text(
          '$rank',
          style: theme.textTheme.labelMedium?.copyWith(
            color: recColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.stock.name,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _RecBadge(label: recLabel, color: recColor),
        ],
      ),
      subtitle: Text(
        [
          item.stock.symbol,
          if (analyst.numberOfAnalysts != null)
            '${analyst.numberOfAnalysts} analysts',
          if (upsideStr != null) upsideStr,
          if (item.hasPrice)
            CurrencyFormatter.format(item.currentPrice, item.stock.currency),
        ].join(' · '),
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: analyst.targetMeanPrice.isPositive
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.format(
                      analyst.targetMeanPrice, item.stock.currency),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  'target',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

class _RecBadge extends StatelessWidget {
  const _RecBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
}
