import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/calculators/pnl_calculator.dart';
import '../../core/calculators/portfolio_calculator.dart';
import '../../core/models/analyst_data.dart';
import '../../core/models/dividend.dart';
import '../../core/models/exchange_rate.dart';
import '../../core/models/price_quote.dart';
import '../../core/models/stock.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/decimal_math.dart';
import '../settings/settings_provider.dart';
import '../transactions/widgets/transaction_tile.dart';
import '../dividends/widgets/confirm_dividend_dialog.dart';
import '../dividends/widgets/dividend_tile.dart';
import 'stocks_provider.dart';
import 'widgets/manual_price_dialog.dart';

class StockDetailScreen extends ConsumerStatefulWidget {
  const StockDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends ConsumerState<StockDetailScreen> {
  bool _isSyncingDividends = false;

  Future<void> _syncDividends(Stock stock) async {
    if (_isSyncingDividends) return;
    setState(() => _isSyncingDividends = true);
    try {
      final txs =
          ref.read(transactionsByStockProvider(stock.id)).value ?? [];
      final splits =
          ref.read(splitsByStockProvider(stock.id)).value ?? [];
      final fetched = await ref
          .read(marketDataServiceProvider)
          .fetchDividends(stock.symbol);
      if (!mounted) return;
      await ref.read(stockActionsProvider).syncDividends(
            stock.id,
            stock.currency,
            stock.isin,
            fetched,
            txs,
            splits,
          );
    } catch (e) {
      debugPrint('StockDetail: dividend sync failed: $e');
    } finally {
      if (mounted) setState(() => _isSyncingDividends = false);
    }
  }

  Future<void> _confirmDividend(Dividend dividend) async {
    final confirmed = await showDialog<Dividend>(
      context: context,
      builder: (_) => ConfirmDividendDialog(dividend: dividend),
    );
    if (confirmed == null || !mounted) return;
    try {
      await ref.read(stockActionsProvider).confirmDividend(confirmed);
    } catch (e) {
      debugPrint('StockDetail: confirmDividend failed: $e');
    }
  }

  void _showManualPriceDialog(Stock stock) {
    final notifier = ref.read(priceQuotesProvider.notifier);

    showDialog<({String currency, Decimal price})>(
      context: context,
      builder: (ctx) => ManualPriceDialog(initialCurrency: stock.currency),
    ).then((result) async {
      if (result == null) return;
      try {
        await ref
            .read(stockActionsProvider)
            .setManualPrice(stock.id, result.price, result.currency);
        final quote = PriceQuote(
          stockId: stock.id,
          price: result.price,
          currency: result.currency,
          fetchedAt: DateTime.now(),
          isManualOverride: true,
        );
        final updated = Map<String, PriceQuote>.from(notifier.state);
        updated[stock.id] = quote;
        notifier.state = updated;
      } catch (e) {
        debugPrint('StockDetail: setManualPrice failed: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(stockByIdProvider(widget.id));
    final txsAsync = ref.watch(transactionsByStockProvider(widget.id));
    final splitsAsync = ref.watch(splitsByStockProvider(widget.id));
    final dividendsAsync = ref.watch(dividendsByStockProvider(widget.id));
    final analystAsync = ref.watch(analystDataProvider(widget.id));
    final quotes = ref.watch(priceQuotesProvider);
    final rates = ref.watch(exchangeRatesProvider).value ?? [];

    return stockAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (stock) {
        if (stock == null) {
          return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('Stock not found')));
        }

        final txs = txsAsync.value ?? [];
        final splits = splitsAsync.value ?? [];
        final quote = quotes[stock.id];
        final rawQuotePrice = quote?.price;
        final quoteCurrency = quote?.currency ?? stock.currency;

        Decimal? currentPrice;
        if (rawQuotePrice != null) {
          if (quoteCurrency == stock.currency) {
            currentPrice = rawQuotePrice;
          } else {
            final adjRate =
                ExchangeRate.find(rates, quoteCurrency, stock.currency);
            if (adjRate != null) currentPrice = adjRate.convert(rawQuotePrice);
          }
        }

        final position = PortfolioCalculator.calculate(txs, splits);

        PnlResult? pnl;
        if (currentPrice != null) {
          pnl = PnlCalculator.calculate(
            transactions: txs,
            splits: splits,
            currentPrice: currentPrice,
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(stock.symbol),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => context.push('/stocks/${widget.id}/edit'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Stock info card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stock.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '${stock.exchange} · ${stock.isin}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                      const Divider(height: 24),
                      _kv(context, 'Shares held',
                          position.sharesHeld.toStringAsFixed(6)),
                      _kv(
                          context,
                          'Avg buy price',
                          CurrencyFormatter.format(
                              position.avgBuyPrice, stock.currency)),
                      _kv(
                          context,
                          'Invested',
                          CurrencyFormatter.format(
                              position.totalInvested, stock.currency)),
                      if (currentPrice != null) ...[
                        _kv(
                          context,
                          'Current price',
                          _currentPriceLabel(
                            currentPrice,
                            stock.currency,
                            rawQuotePrice!,
                            quoteCurrency,
                            quote!.withStaleness().isStale,
                            quote.isManualOverride,
                          ),
                        ),
                        if (quote.isManualOverride)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () async {
                                final notifier =
                                    ref.read(priceQuotesProvider.notifier);
                                try {
                                  await ref
                                      .read(stockActionsProvider)
                                      .clearManualPrice(stock.id);
                                  final updated =
                                      Map<String, PriceQuote>.from(
                                          notifier.state);
                                  updated.remove(stock.id);
                                  notifier.state = updated;
                                } catch (e) {
                                  debugPrint(
                                      'StockDetail: clearManualPrice failed: $e');
                                }
                              },
                              child: const Text('Clear manual price'),
                            ),
                          ),
                      ] else ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Current price',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _showManualPriceDialog(stock),
                                child: const Text('Set price'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (pnl != null) ...[
                        _kv(
                          context,
                          'Unrealised P&L',
                          '${CurrencyFormatter.format(pnl.unrealisedPnl, stock.currency)} '
                              '(${CurrencyFormatter.formatPercent(pnl.unrealisedPnlPct)})',
                          valueColor: pnl.unrealisedPnl.isNegative
                              ? Theme.of(context).colorScheme.error
                              : Colors.green,
                        ),
                        _kv(
                          context,
                          'Realised P&L',
                          CurrencyFormatter.format(
                              pnl.realisedPnl, stock.currency),
                          valueColor: pnl.realisedPnl.isNegative
                              ? Theme.of(context).colorScheme.error
                              : Colors.green,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Analysis card
              if (analystAsync.value != null)
                _buildAnalystCard(context, analystAsync.value!, stock.currency),
              if (analystAsync.value != null) const SizedBox(height: 16),

              _sectionHeader(
                context,
                'Transactions',
                onAdd: () => context
                    .push('/stocks/${widget.id}/transactions/add'),
              ),
              txsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
                data: (txs) => txs.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No transactions yet.'),
                      )
                    : Column(
                        children: txs
                            .map((tx) => TransactionTile(
                                  transaction: tx,
                                  currency: stock.currency,
                                  onTap: () => context.push(
                                      '/stocks/${widget.id}/transactions/${tx.id}/edit'),
                                ))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 16),

              _sectionHeader(
                context,
                'Dividends',
                onAdd: () =>
                    context.push('/stocks/${widget.id}/dividends/add'),
                onSync: () => _syncDividends(stock),
                isSyncing: _isSyncingDividends,
              ),
              dividendsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
                data: (divs) => divs.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No dividends recorded yet.'),
                      )
                    : Column(
                        children: divs
                            .map((d) => DividendTile(
                                  dividend: d,
                                  onTap: () => context.push(
                                      '/stocks/${widget.id}/dividends/${d.id}/edit'),
                                  onConfirm: d.isPendingConfirmation
                                      ? () => _confirmDividend(d)
                                      : null,
                                ))
                            .toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    String title, {
    required VoidCallback onAdd,
    VoidCallback? onSync,
    bool isSyncing = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        Row(
          children: [
            if (onSync != null)
              isSyncing
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.sync, size: 18),
                      onPressed: onSync,
                      tooltip: 'Sync from market data',
                    ),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }

  String _currentPriceLabel(
    Decimal price,
    String stockCurrency,
    Decimal rawPrice,
    String quoteCurrency,
    bool isStale,
    bool isManual,
  ) {
    final tag = isManual ? ' (manual)' : (isStale ? ' (stale)' : '');
    final converted = CurrencyFormatter.format(price, stockCurrency);
    if (quoteCurrency == stockCurrency) return '$converted$tag';
    final raw = CurrencyFormatter.format(rawPrice, quoteCurrency);
    return '$converted ($raw)$tag';
  }

  Widget _kv(BuildContext context, String label, String value,
      {Color? valueColor}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(value,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: valueColor)),
        ],
      ),
    );
  }

  Widget _buildAnalystCard(
      BuildContext context, AnalystData data, String stockCurrency) {
    final currency = data.currency ?? stockCurrency;
    final theme = Theme.of(context);
    final (recLabel, recColor) = _recommendationStyle(data.recommendationKey);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Analysis',
                    style: theme.textTheme.titleMedium),
                if (data.numberOfAnalysts != null)
                  Text(
                    '${data.numberOfAnalysts} analysts',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (recLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Chip(
                  label: Text(
                    recLabel,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: recColor,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            _kv(context, 'Target price',
                CurrencyFormatter.format(data.targetMeanPrice, currency)),
            if (data.targetLowPrice != null && data.targetHighPrice != null)
              _kv(
                context,
                'Target range',
                '${CurrencyFormatter.format(data.targetLowPrice!, currency)}'
                    ' – ${CurrencyFormatter.format(data.targetHighPrice!, currency)}',
              ),
          ],
        ),
      ),
    );
  }

  (String?, Color) _recommendationStyle(String? key) {
    return switch (key?.toLowerCase()) {
      'strongbuy' => ('Strong Buy', Colors.green.shade700),
      'buy' => ('Buy', Colors.green),
      'hold' => ('Hold', Colors.amber.shade700),
      'underperform' => ('Underperform', Colors.orange),
      'sell' => ('Sell', Colors.red),
      _ => (null, Colors.transparent),
    };
  }
}
