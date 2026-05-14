import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/decimal_math.dart';
import '../dashboard_provider.dart';

class PortfolioSummaryCard extends StatelessWidget {
  const PortfolioSummaryCard({super.key, required this.summary});

  final PortfolioSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Portfolio', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _Row(
              label: 'Total value',
              value: CurrencyFormatter.format(
                  summary.totalValue, summary.currency),
              style: theme.textTheme.headlineSmall,
            ),
            const Divider(height: 24),
            _Row(
              label: 'Invested',
              value: CurrencyFormatter.format(
                  summary.totalInvested, summary.currency),
            ),
            _Row(
              label: 'Unrealised P&L',
              value:
                  '${CurrencyFormatter.format(summary.unrealisedPnl, summary.currency)} '
                  '(${CurrencyFormatter.formatPercent(summary.unrealisedPnlPct)})',
              valueColor: summary.unrealisedPnl.isNegative
                  ? theme.colorScheme.error
                  : Colors.green,
            ),
            _Row(
              label: 'Realised P&L',
              value: CurrencyFormatter.format(
                  summary.realisedPnl, summary.currency),
              valueColor: summary.realisedPnl.isNegative
                  ? theme.colorScheme.error
                  : Colors.green,
            ),
            const Divider(height: 24),
            _Row(
              label: 'Dividends (all-time)',
              value: CurrencyFormatter.format(
                  summary.allTimeDividends, summary.currency),
            ),
            _Row(
              label: 'Dividends (this year)',
              value: CurrencyFormatter.format(
                  summary.currentYearDividends, summary.currency),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.style,
    this.valueColor,
  });

  final String label;
  final String value;
  final TextStyle? style;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: style ?? theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
          Text(value,
              style: (style ?? theme.textTheme.bodyMedium)
                  ?.copyWith(color: valueColor)),
        ],
      ),
    );
  }
}
