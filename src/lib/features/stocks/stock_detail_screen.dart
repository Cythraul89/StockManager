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
              analystAsync.when(
                loading: () => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Text('Analysis',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(width: 12),
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ),
                  ),
                ),
                error: (_, __) => _buildAnalystUnavailableCard(context),
                data: (data) => data != null
                    ? _buildAnalystCard(
                        context, data, stock.currency, quoteCurrency,
                        currentPrice, rates)
                    : _buildAnalystUnavailableCard(context),
              ),
              const SizedBox(height: 16),

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

  Widget _buildAnalystUnavailableCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Analysis',
                style: Theme.of(context).textTheme.titleMedium),
            Text(
              'No data available',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalystCard(
    BuildContext context,
    AnalystData data,
    String stockCurrency,
    String quoteCurrency,
    Decimal? currentPrice,
    List<ExchangeRate> rates,
  ) {
    // Convert analyst prices to stockCurrency when Yahoo reports them in a
    // different currency (e.g. USD for ARM ADR, NOK for Norwegian stocks).
    // Fall back to quoteCurrency when Yahoo omits financialCurrency — analyst
    // targets are always denominated in the stock's primary trading currency.
    final analysisCurrency = data.currency ?? quoteCurrency;
    final ExchangeRate? convRate = analysisCurrency != stockCurrency
        ? ExchangeRate.find(rates, analysisCurrency, stockCurrency)
        : null;

    // Prices are comparable to currentPrice (always in stockCurrency) when:
    //   • currencies already match, OR
    //   • a conversion rate was found.
    final pricesInStockCurrency =
        analysisCurrency == stockCurrency || convRate != null;
    final currency = pricesInStockCurrency ? stockCurrency : analysisCurrency;

    // Convert a single price from analysisCurrency → stockCurrency.
    Decimal conv(Decimal price) =>
        convRate != null ? convRate.convert(price) : price;

    final targetMean = conv(data.targetMeanPrice);
    final targetLow =
        data.targetLowPrice != null ? conv(data.targetLowPrice!) : null;
    final targetHigh =
        data.targetHighPrice != null ? conv(data.targetHighPrice!) : null;
    final fiftyTwoLow =
        data.fiftyTwoWeekLow != null ? conv(data.fiftyTwoWeekLow!) : null;
    final fiftyTwoHigh =
        data.fiftyTwoWeekHigh != null ? conv(data.fiftyTwoWeekHigh!) : null;
    final epsConverted =
        data.trailingEps != null ? conv(data.trailingEps!) : null;

    final theme = Theme.of(context);
    final (recLabel, recColor) = _recommendationStyle(data.recommendationKey);

    final canCompare =
        currentPrice != null && currentPrice.isPositive && pricesInStockCurrency;
    final upside =
        canCompare ? targetMean.percentChangeFrom(currentPrice) : null;
    final upsideColor = upside == null
        ? null
        : (upside.isNegative ? theme.colorScheme.error : Colors.green.shade600);

    // Consensus counts
    final totalConsensus = (data.strongBuyCount ?? 0) +
        (data.buyCount ?? 0) +
        (data.holdCount ?? 0) +
        (data.sellCount ?? 0) +
        (data.strongSellCount ?? 0);
    final hasConsensus = totalConsensus > 0;

    final hasValuation =
        data.trailingPE != null || data.forwardPE != null || epsConverted != null;
    final has52Week = fiftyTwoLow != null && fiftyTwoHigh != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Analysis', style: theme.textTheme.titleMedium),
                if (data.numberOfAnalysts != null)
                  Text(
                    '${data.numberOfAnalysts} analysts',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Recommendation chip ────────────────────────────────────────
            if (recLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Chip(
                  label: Text(recLabel,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  backgroundColor: recColor,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),

            // ── Target price with % upside/downside ───────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Target price',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        CurrencyFormatter.format(targetMean, currency),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: upsideColor),
                      ),
                      if (upside != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            '${upside.isNegative ? '' : '+'}${upside.toStringFixed(1)}%',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: upsideColor),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Analyst target range bar ───────────────────────────────────
            if (targetLow != null && targetHigh != null)
              _buildRangeBar(
                context,
                low: targetLow,
                high: targetHigh,
                current: canCompare ? currentPrice : null,
                currency: currency,
              ),

            // ── 52-week range bar ──────────────────────────────────────────
            if (has52Week) ...[
              const SizedBox(height: 14),
              _analyticsSubheader(context, '52-Week Range'),
              _buildRangeBar(
                context,
                low: fiftyTwoLow,
                high: fiftyTwoHigh,
                current: canCompare ? currentPrice : null,
                currency: currency,
              ),
            ],

            // ── Analyst consensus breakdown bar ────────────────────────────
            if (hasConsensus) ...[
              const SizedBox(height: 14),
              _analyticsSubheader(context, 'Consensus'),
              _buildConsensusBar(context, data, totalConsensus),
            ],

            // ── Valuation ──────────────────────────────────────────────────
            if (hasValuation) ...[
              const SizedBox(height: 14),
              _analyticsSubheader(context, 'Valuation'),
              if (data.trailingPE != null)
                _kv(context, 'P/E (trailing)',
                    '${data.trailingPE!.toStringFixed(1)}×'),
              if (data.forwardPE != null)
                _kv(context, 'P/E (forward)',
                    '${data.forwardPE!.toStringFixed(1)}×'),
              if (epsConverted != null)
                _kv(context, 'EPS (TTM)',
                    CurrencyFormatter.format(epsConverted, currency)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _analyticsSubheader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildConsensusBar(
      BuildContext context, AnalystData data, int total) {
    final theme = Theme.of(context);

    final segments = [
      (count: data.strongBuyCount ?? 0, color: Colors.green.shade800),
      (count: data.buyCount ?? 0, color: Colors.green.shade500),
      (count: data.holdCount ?? 0, color: Colors.amber.shade600),
      (count: data.sellCount ?? 0, color: Colors.orange.shade700),
      (count: data.strongSellCount ?? 0, color: Colors.red.shade700),
    ].where((s) => s.count > 0).toList();

    final parts = [
      if ((data.strongBuyCount ?? 0) > 0) '${data.strongBuyCount} Str.Buy',
      if ((data.buyCount ?? 0) > 0) '${data.buyCount} Buy',
      if ((data.holdCount ?? 0) > 0) '${data.holdCount} Hold',
      if ((data.sellCount ?? 0) > 0) '${data.sellCount} Sell',
      if ((data.strongSellCount ?? 0) > 0) '${data.strongSellCount} Str.Sell',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 8,
            child: Row(
              children: segments
                  .map((s) => Expanded(
                        flex: s.count,
                        child: Container(color: s.color),
                      ))
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          parts.join(' · '),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Horizontal gradient bar (red → green) showing a price range.
  /// A small marker indicates where [current] sits within [low]..[high].
  Widget _buildRangeBar(
    BuildContext context, {
    required Decimal low,
    required Decimal high,
    required Decimal? current,
    required String currency,
  }) {
    final theme = Theme.of(context);
    final rangeDouble = (high - low).toDouble();
    final fraction = (current != null && rangeDouble > 0)
        ? ((current - low).toDouble() / rangeDouble).clamp(0.0, 1.0)
        : null;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            const markerW = 10.0;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.red.shade400,
                      Colors.amber.shade400,
                      Colors.green.shade500,
                    ]),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                if (fraction != null)
                  Positioned(
                    left: (constraints.maxWidth * fraction - markerW / 2)
                        .clamp(0.0, constraints.maxWidth - markerW),
                    top: -3,
                    child: Container(
                      width: markerW,
                      height: 12,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                            color: theme.colorScheme.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                CurrencyFormatter.format(low, currency),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (current != null)
                Text(
                  CurrencyFormatter.format(current, currency),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                CurrencyFormatter.format(high, currency),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  (String?, Color) _recommendationStyle(String? key) {
    return switch (key?.toLowerCase()) {
      'strongbuy' || 'strong_buy' => ('Strong Buy', Colors.green.shade800),
      'buy' => ('Buy', Colors.green.shade600),
      'hold' => ('Hold', Colors.amber.shade700),
      'underperform' => ('Underperform', Colors.orange.shade700),
      'sell' || 'strongsell' || 'strong_sell' => ('Sell', Colors.red),
      _ => (null, Colors.transparent),
    };
  }
}
