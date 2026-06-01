import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/price_quote.dart';
import '../../core/utils/decimal_math.dart';
import '../settings/settings_provider.dart';
import '../stocks/stocks_provider.dart';
import 'dashboard_provider.dart';
import 'widgets/allocation_chart.dart';
import 'widgets/portfolio_summary_card.dart';
import 'widgets/stock_list_tile.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _hideClosedPositions = false;

  @override
  void initState() {
    super.initState();
    _refreshPrices();
  }

  Future<void> _refreshPrices() async {
    await Future.wait([_fetchQuotes(), _fetchRates()]);
  }

  Future<void> _fetchQuotes() async {
    try {
      final stocks = await ref.read(stocksStreamProvider.future);
      final symbolMap = {for (final s in stocks) s.id: s.symbol};
      final currencyMap = {for (final s in stocks) s.id: s.currency};

      final actions = ref.read(stockActionsProvider);
      final marketQuotes = await ref
          .read(marketDataServiceProvider)
          .fetchQuotes(symbolMap, currencyByStockId: currencyMap);

      // Persist fresh market prices to DB cache.
      await Future.wait(marketQuotes.values.map(actions.cacheMarketPrice));

      // Fill in manual overrides for stocks with no market data.
      final allQuotes = Map<String, PriceQuote>.from(marketQuotes);
      final manualPrices = await actions.loadManualPrices();
      for (final entry in manualPrices.entries) {
        if (!allQuotes.containsKey(entry.key)) {
          allQuotes[entry.key] = entry.value;
        }
      }

      if (mounted) ref.read(priceQuotesProvider.notifier).state = allQuotes;
    } catch (e) {
      debugPrint('DashboardScreen: fetchQuotes failed: $e');
    }
  }

  Future<void> _fetchRates() async {
    try {
      final settings = await ref.read(settingsProvider.future);
      final rates = await ref
          .read(currencyServiceProvider)
          .fetchRates(settings.preferredCurrency);
      if (rates.isNotEmpty) {
        await ref
            .read(settingsActionsProvider)
            .cacheRates(rates.values.toList());
      }
    } catch (e) {
      debugPrint('DashboardScreen: fetchRates failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-refresh prices whenever a stock is added.
    ref.listen(stocksStreamProvider, (prev, next) {
      final prevLen = prev?.value?.length ?? 0;
      final nextLen = next.value?.length ?? 0;
      if (nextLen > prevLen) _refreshPrices();
    });

    final summaryAsync = ref.watch(portfolioSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: Icon(
              _hideClosedPositions
                  ? Icons.visibility_off
                  : Icons.visibility_outlined,
            ),
            tooltip: _hideClosedPositions
                ? 'Show closed positions'
                : 'Hide closed positions',
            onPressed: () =>
                setState(() => _hideClosedPositions = !_hideClosedPositions),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh prices',
            onPressed: _refreshPrices,
          ),
        ],
      ),
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (summary) {
          final allItems = summary.stockItems;
          final displayItems = _hideClosedPositions
              ? allItems.where((i) => i.sharesHeld.isPositive).toList()
              : allItems;
          final hiddenCount = allItems.length - displayItems.length;

          return RefreshIndicator(
            onRefresh: _refreshPrices,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                PortfolioSummaryCard(summary: summary),
                const SizedBox(height: 16),
                AllocationChart(summary: summary),
                const SizedBox(height: 16),
                if (allItems.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No stocks yet. Add one to get started.'),
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Text(
                        'Holdings',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (hiddenCount > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '($hiddenCount closed hidden)',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (displayItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'All positions are closed.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    )
                  else
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (int i = 0; i < displayItems.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            StockListTile(item: displayItems[i]),
                          ],
                        ],
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
