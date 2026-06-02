import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/dashboard_provider.dart';
import '../dashboard/widgets/portfolio_history_chart.dart';
import '../dashboard/widgets/stock_list_tile.dart';

class PortfolioAnalysisScreen extends ConsumerWidget {
  const PortfolioAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(portfolioHistoryProvider);
    final summaryAsync = ref.watch(portfolioSummaryProvider);

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Analysis')),
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (summary) {
          final items =
              summary.stockItems.where((i) => i.sharesHeld.isPositive).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Portfolio history chart — shown once loaded, silently absent
              // while data is loading so the rest of the page is always visible.
              if (historyAsync.value != null &&
                  historyAsync.value!.isNotEmpty) ...[
                PortfolioHistoryChart(points: historyAsync.value!),
                const SizedBox(height: 16),
              ],

              // Holdings
              Text('Holdings', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No open positions.\nAdd transactions to get started.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (int i = 0; i < items.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        StockListTile(item: items[i]),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
