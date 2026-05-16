import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/price_quote.dart';
import '../../core/models/stock.dart';
import 'stocks_provider.dart';
import 'widgets/stock_card.dart';

enum _SortField { symbol, name, price }

class StocksScreen extends ConsumerStatefulWidget {
  const StocksScreen({super.key});

  @override
  ConsumerState<StocksScreen> createState() => _StocksScreenState();
}

class _StocksScreenState extends ConsumerState<StocksScreen> {
  final _searchController = TextEditingController();
  _SortField _sortBy = _SortField.symbol;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Stock> _applyFilterAndSort(
      List<Stock> stocks, Map<String, PriceQuote> quotes) {
    final q = _searchController.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? List.of(stocks)
        : stocks
            .where((s) =>
                s.symbol.toLowerCase().contains(q) ||
                s.name.toLowerCase().contains(q))
            .toList();

    filtered.sort((a, b) {
      switch (_sortBy) {
        case _SortField.symbol:
          return a.symbol.compareTo(b.symbol);
        case _SortField.name:
          return a.name.compareTo(b.name);
        case _SortField.price:
          // High → low; stocks with no quote sort to the end.
          final pa = quotes[a.id]?.price.toDouble();
          final pb = quotes[b.id]?.price.toDouble();
          if (pa == null && pb == null) return 0;
          if (pa == null) return 1;
          if (pb == null) return -1;
          return pb.compareTo(pa);
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final stocksAsync = ref.watch(stocksStreamProvider);
    final quotes = ref.watch(priceQuotesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stocks'),
        actions: [
          PopupMenuButton<_SortField>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onSelected: (f) => setState(() => _sortBy = f),
            itemBuilder: (ctx) => [
              _sortMenuItem(ctx, _SortField.symbol, 'Symbol'),
              _sortMenuItem(ctx, _SortField.name, 'Name'),
              _sortMenuItem(ctx, _SortField.price, 'Price (high → low)'),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/stocks/add'),
        tooltip: 'Add stock',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by symbol or name…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () =>
                            setState(() => _searchController.clear()),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: stocksAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (stocks) {
                if (stocks.isEmpty) {
                  return const Center(
                    child: Text(
                      'No stocks yet.\nTap + to add one.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final visible = _applyFilterAndSort(stocks, quotes);

                if (visible.isEmpty) {
                  return Center(
                    child: Text(
                      'No results for "${_searchController.text.trim()}"',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => StockCard(stock: visible[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_SortField> _sortMenuItem(
      BuildContext context, _SortField field, String label) {
    final active = _sortBy == field;
    final theme = Theme.of(context);
    return PopupMenuItem(
      value: field,
      child: Row(
        children: [
          Text(label),
          if (active) ...[
            const Spacer(),
            Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
          ],
        ],
      ),
    );
  }
}
