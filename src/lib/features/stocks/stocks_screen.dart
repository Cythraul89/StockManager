import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'stocks_provider.dart';
import 'widgets/stock_card.dart';

class StocksScreen extends ConsumerWidget {
  const StocksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stocksAsync = ref.watch(stocksStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Stocks')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/stocks/add'),
        tooltip: 'Add stock',
        child: const Icon(Icons.add),
      ),
      body: stocksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (stocks) {
          if (stocks.isEmpty) {
            return const Center(
              child: Text('No stocks yet.\nTap + to add one.',
                  textAlign: TextAlign.center),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: stocks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => StockCard(stock: stocks[i]),
          );
        },
      ),
    );
  }
}
