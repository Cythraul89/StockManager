import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/calculators/pnl_calculator.dart';
import '../../core/calculators/portfolio_calculator.dart';
import '../../core/models/exchange_rate.dart';
import '../../core/models/price_quote.dart';
import '../../core/models/stock.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/decimal_math.dart';
import '../settings/settings_provider.dart';
import '../transactions/widgets/transaction_tile.dart';
import '../dividends/widgets/dividend_tile.dart';
import 'stocks_provider.dart';

class StockDetailScreen extends ConsumerWidget {
  const StockDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(stockByIdProvider(id));
    final txsAsync = ref.watch(transactionsByStockProvider(id));
    final splitsAsync = ref.watch(splitsByStockProvider(id));
    final dividendsAsync = ref.watch(dividendsByStockProvider(id));
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

        // Convert price from quoteCurrency to stock.currency so P&L arithmetic
        // uses the same unit as the stored transaction prices.
        Decimal? currentPrice;
        if (rawQuotePrice != null) {
          if (quoteCurrency == stock.currency) {
            currentPrice = rawQuotePrice;
          } else {
            final adjRate = ExchangeRate.find(rates, quoteCurrency, stock.currency);
            currentPrice = adjRate != null
                ? adjRate.convert(rawQuotePrice)
                : rawQuotePrice;
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
                onPressed: () => context.push('/stocks/$id/edit'),
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
                      Text('${stock.exchange} · ${stock.isin}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                      const Divider(height: 24),
                      _kv('Shares held',
                          position.sharesHeld.toStringAsFixed(6)),
                      _kv('Avg buy price',
                          CurrencyFormatter.format(
                              position.avgBuyPrice, stock.currency)),
                      _kv('Invested',
                          CurrencyFormatter.format(
                              position.totalInvested, stock.currency)),
                      if (currentPrice != null) ...[
                        _kv('Current price',
                            _currentPriceLabel(
                                currentPrice, stock.currency,
                                rawQuotePrice!, quoteCurrency,
                                quote!.withStaleness().isStale,
                                quote.isManualOverride)),
                        if (quote.isManualOverride)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                final notifier =
                                    ref.read(priceQuotesProvider.notifier);
                                ref
                                    .read(stockActionsProvider)
                                    .clearManualPrice(stock.id)
                                    .then((_) {
                                  final updated = Map<String, PriceQuote>.from(
                                      notifier.state);
                                  updated.remove(stock.id);
                                  notifier.state = updated;
                                });
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
                                onPressed: () => _showManualPriceDialog(
                                    context, ref, stock),
                                child: const Text('Set price'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (pnl != null) ...[
                        _kv(
                          'Unrealised P&L',
                          '${CurrencyFormatter.format(pnl.unrealisedPnl, stock.currency)} '
                              '(${CurrencyFormatter.formatPercent(pnl.unrealisedPnlPct)})',
                          valueColor: pnl.unrealisedPnl.isNegative
                              ? Theme.of(context).colorScheme.error
                              : Colors.green,
                        ),
                        _kv(
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

              _sectionHeader(context, 'Transactions',
                  () => context.push('/stocks/$id/transactions/add')),
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
                                transaction: tx, currency: stock.currency))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 16),

              _sectionHeader(context, 'Dividends',
                  () => context.push('/stocks/$id/dividends/add')),
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
                            .map((d) => DividendTile(dividend: d))
                            .toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String title, VoidCallback onAdd) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add'),
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

  void _showManualPriceDialog(
      BuildContext context, WidgetRef ref, Stock stock) {
    final notifier = ref.read(priceQuotesProvider.notifier);

    showDialog<({String currency, Decimal price})>(
      context: context,
      builder: (ctx) => _ManualPriceDialog(initialCurrency: stock.currency),
    ).then((result) {
      if (result == null) return;
      ref
          .read(stockActionsProvider)
          .setManualPrice(stock.id, result.price, result.currency)
          .then((_) {
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
      });
    });
  }

  Widget _kv(String label, String value, {Color? valueColor}) {
    return Builder(builder: (context) {
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
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: valueColor)),
          ],
        ),
      );
    });
  }
}

class _ManualPriceDialog extends StatefulWidget {
  const _ManualPriceDialog({required this.initialCurrency});

  final String initialCurrency;

  @override
  State<_ManualPriceDialog> createState() => _ManualPriceDialogState();
}

class _ManualPriceDialogState extends State<_ManualPriceDialog> {
  final _controller = TextEditingController();
  late String _currency;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _currency = widget.initialCurrency;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set manual price'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Price',
              errorText: _errorText,
            ),
            autofocus: true,
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _currency,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: CurrencyFormatter.supportedCurrencies
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _currency = v);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final price = Decimal.tryParse(_controller.text.trim());
            if (price == null || price.compareTo(Decimal.zero) <= 0) {
              setState(() => _errorText = 'Enter a positive number');
              return;
            }
            Navigator.of(context).pop((currency: _currency, price: price));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
