import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_helpers.dart';
import '../stocks/stocks_provider.dart';
import 'widgets/confirm_dividend_dialog.dart';
import 'widgets/dividend_income_chart.dart';
import 'widgets/dividend_tile.dart';
import '../../core/models/dividend.dart';

class DividendsScreen extends ConsumerWidget {
  const DividendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dividendsAsync = ref.watch(allDividendsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dividends')),
      body: dividendsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (dividends) {
          final pending = dividends
              .where((d) => d.isPendingConfirmation)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          final paid = dividends
              .where((d) => d.type == DividendType.paid && !d.isPendingConfirmation)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          final expected = dividends
              .where((d) => d.type == DividendType.expected)
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));

          final upcomingExpected = expected
              .where((d) => DateHelpers.daysUntil(d.date) >= 0)
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DividendIncomeChart(dividends: dividends),
              const SizedBox(height: 16),
              if (pending.isNotEmpty) ...[
                Text('Pending confirmation',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.orange)),
                const SizedBox(height: 4),
                Text(
                  'Review auto-fetched dividends to include them in calculations.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: pending
                        .map((d) => DividendTile(
                              dividend: d,
                              onTap: () => context.push(
                                  '/stocks/${d.stockId}/dividends/${d.id}/edit'),
                              onConfirm: () => _confirmDividend(context, ref, d),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (upcomingExpected.isNotEmpty) ...[
                Text('Upcoming',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: upcomingExpected
                        .map((d) => DividendTile(
                              dividend: d,
                              onTap: () => context.push(
                                  '/stocks/${d.stockId}/dividends/${d.id}/edit'),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text('Paid',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (paid.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No paid dividends recorded yet.'),
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: paid
                        .map((d) => DividendTile(
                              dividend: d,
                              onTap: () => context.push(
                                  '/stocks/${d.stockId}/dividends/${d.id}/edit'),
                            ))
                        .toList(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDividend(
      BuildContext context, WidgetRef ref, Dividend dividend) async {
    final confirmed = await showDialog<Dividend>(
      context: context,
      builder: (_) => ConfirmDividendDialog(dividend: dividend),
    );
    if (confirmed == null) return;
    try {
      await ref.read(stockActionsProvider).confirmDividend(confirmed);
    } catch (e) {
      debugPrint('DividendsScreen: confirmDividend failed: $e');
    }
  }
}
