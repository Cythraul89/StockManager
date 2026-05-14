import 'package:flutter/material.dart';

import '../../../core/models/dividend.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/decimal_math.dart';

class DividendTile extends StatelessWidget {
  const DividendTile({
    super.key,
    required this.dividend,
    this.onConfirm,
  });

  final Dividend dividend;
  // If provided and the dividend isPendingConfirmation, a confirm button is shown.
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPaid = dividend.type == DividendType.paid;
    final isPending = dividend.isPendingConfirmation;
    final daysUntil = isPaid ? null : DateHelpers.daysUntil(dividend.date);

    final leadingColor =
        isPending ? Colors.orange : (isPaid ? Colors.green : theme.colorScheme.primary);
    final leadingIcon =
        isPending ? Icons.pending_outlined : (isPaid ? Icons.payments : Icons.schedule);

    Widget? trailingWidget;
    if (isPending && onConfirm != null) {
      trailingWidget = TextButton(
        onPressed: onConfirm,
        child: const Text('Review'),
      );
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: leadingColor.withValues(alpha: 0.15),
        child: Icon(leadingIcon, size: 20, color: leadingColor),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                isPending
                    ? 'Pending'
                    : (isPaid ? 'Paid' : 'Expected'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              if (isPending) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'auto',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: Colors.orange),
                  ),
                ),
              ],
            ],
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
        '${isPaid && !isPending && dividend.withholdingTax != null && dividend.withholdingTax!.isPositive ? " · WHT ${CurrencyFormatter.format(dividend.withholdingTax!, dividend.currency)}" : ""}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: trailingWidget,
    );
  }
}
