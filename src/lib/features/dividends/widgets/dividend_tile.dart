import 'package:flutter/material.dart';

import '../../../core/models/dividend.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/decimal_math.dart';

class DividendTile extends StatelessWidget {
  const DividendTile({super.key, required this.dividend});

  final Dividend dividend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPaid = dividend.type == DividendType.paid;
    final daysUntil =
        isPaid ? null : DateHelpers.daysUntil(dividend.date);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (isPaid ? Colors.green : theme.colorScheme.primary)
            .withValues(alpha: 0.15),
        child: Icon(
          isPaid ? Icons.payments : Icons.schedule,
          size: 20,
          color: isPaid ? Colors.green : theme.colorScheme.primary,
        ),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            isPaid ? 'Paid' : 'Expected',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          Text(
            dividend.totalAmount != null
                ? CurrencyFormatter.format(
                    dividend.totalAmount!, dividend.currency)
                : CurrencyFormatter.format(
                    dividend.amountPerShare, dividend.currency),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
      subtitle: Text(
        '${DateHelpers.formatDate(dividend.date)}'
        ' · ${CurrencyFormatter.format(dividend.amountPerShare, dividend.currency)}/share'
        '${!isPaid && daysUntil != null ? " · in $daysUntil days" : ""}'
        '${isPaid && dividend.withholdingTax != null && dividend.withholdingTax!.isPositive ? " · WHT ${CurrencyFormatter.format(dividend.withholdingTax!, dividend.currency)}" : ""}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
