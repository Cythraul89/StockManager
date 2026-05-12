import 'package:flutter/material.dart';

import '../../../core/models/transaction.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/decimal_math.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.currency,
  });

  final StockTransaction transaction;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBuy = transaction.type == TransactionType.buy;
    final typeColor = isBuy ? Colors.green : theme.colorScheme.error;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: typeColor.withOpacity(0.15),
        child: Text(
          isBuy ? 'B' : 'S',
          style: TextStyle(
              color: typeColor, fontWeight: FontWeight.bold),
        ),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${isBuy ? "Buy" : "Sell"} ${transaction.shares.toStringAsFixed(4)}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          Text(
            CurrencyFormatter.format(transaction.totalCost, currency),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
      subtitle: Text(
        '${DateHelpers.formatDateTime(transaction.executedAt)}'
        ' · ${CurrencyFormatter.format(transaction.pricePerShare, currency)}/share'
        '${transaction.fees.isPositive ? " · fees ${CurrencyFormatter.format(transaction.fees, currency)}" : ""}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
