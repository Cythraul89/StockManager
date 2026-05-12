import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_helpers.dart';
import '../settings/settings_provider.dart';
import '../stocks/stocks_provider.dart';
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
          final paid = dividends
              .where((d) => d.type == DividendType.paid)
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
              if (upcomingExpected.isNotEmpty) ...[
                Text('Upcoming',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: upcomingExpected
                        .map((d) => DividendTile(dividend: d))
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
                        .map((d) => DividendTile(dividend: d))
                        .toList(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
