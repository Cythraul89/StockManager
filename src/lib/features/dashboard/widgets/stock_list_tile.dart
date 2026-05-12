import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/decimal_math.dart';
import '../dashboard_provider.dart';

class StockListTile extends StatelessWidget {
  const StockListTile({super.key, required this.item});

  final StockSummaryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pnlColor = item.unrealisedPnlPct.isNegative
        ? theme.colorScheme.error
        : Colors.green;

    return ListTile(
      onTap: () => context.push('/stocks/${item.stock.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.stock.symbol,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(item.stock.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyFormatter.format(item.currentValue, item.stock.currency),
                style: theme.textTheme.bodyMedium,
              ),
              Row(
                children: [
                  if (item.isStale)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.warning_amber_rounded,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  Text(
                    CurrencyFormatter.formatPercent(item.unrealisedPnlPct),
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
        '${item.sharesHeld.toStringAsFixed(4)} shares '
        '@ ${CurrencyFormatter.format(item.currentPrice, item.stock.currency)}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
