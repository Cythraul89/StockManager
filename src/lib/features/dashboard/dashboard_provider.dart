import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/calculators/dividend_calculator.dart';
import '../../core/calculators/pnl_calculator.dart';
import '../../core/calculators/portfolio_calculator.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/broker.dart';
import '../../core/models/dividend.dart';
import '../../core/models/exchange_rate.dart';
import '../../core/models/price_quote.dart';
import '../../core/models/stock.dart';
import '../settings/settings_provider.dart';
import '../stocks/stocks_provider.dart';

class PortfolioSummary {
  const PortfolioSummary({
    required this.totalValue,
    required this.totalInvested,
    required this.unrealisedPnl,
    required this.unrealisedPnlPct,
    required this.realisedPnl,
    required this.allTimeDividends,
    required this.currentYearDividends,
    required this.currency,
    required this.stockItems,
  });

  final Decimal totalValue;
  final Decimal totalInvested;
  final Decimal unrealisedPnl;
  final Decimal unrealisedPnlPct;
  final Decimal realisedPnl;
  final Decimal allTimeDividends;
  final Decimal currentYearDividends;
  final String currency;
  final List<StockSummaryItem> stockItems;
}

class StockSummaryItem {
  const StockSummaryItem({
    required this.stock,
    required this.broker,
    required this.sharesHeld,
    required this.avgBuyPrice,
    required this.currentPrice,
    required this.rawQuotePrice,
    required this.quoteCurrency,
    required this.preferredCurrency,
    required this.currentValue,
    required this.unrealisedPnl,
    required this.unrealisedPnlPct,
    required this.annualYieldPct,
    required this.isStale,
    required this.hasPrice,
    required this.missingRate,
  });

  final Stock stock;
  final Broker? broker;
  final Decimal sharesHeld;
  final Decimal avgBuyPrice;
  // Price in stock.currency (quote price converted from quoteCurrency if they differ).
  final Decimal currentPrice;
  // Raw price as returned by the market-data source, in quoteCurrency.
  final Decimal rawQuotePrice;
  final String quoteCurrency;
  // The user's preferred display currency — currentValue and unrealisedPnl are in this unit.
  final String preferredCurrency;
  final Decimal currentValue;
  final Decimal unrealisedPnl;
  final Decimal unrealisedPnlPct;
  final Decimal annualYieldPct;
  final bool isStale;
  final bool hasPrice;
  // True when a required exchange rate is missing (price or portfolio conversion).
  final bool missingRate;
}

final portfolioSummaryProvider =
    FutureProvider<PortfolioSummary>((ref) async {
  final stocks = await ref.watch(stocksStreamProvider.future);
  final brokers = await ref.watch(brokersStreamProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  // Watch the rates stream directly (not .future) so this provider
  // re-runs whenever new rates are written to the DB.
  final rates = ref.watch(exchangeRatesProvider).value ?? [];
  final quotes = ref.watch(priceQuotesProvider);

  return _buildSummary(stocks, brokers, settings, rates, quotes, ref);
});

PortfolioSummary _buildSummary(
  List<Stock> stocks,
  List<Broker> brokers,
  AppSettings settings,
  List<ExchangeRate> rates,
  Map<String, PriceQuote> quotes,
  Ref ref,
) {
  final brokerById = {for (final b in brokers) b.id: b};
  final preferred = settings.preferredCurrency;

  Decimal totalValue = Decimal.zero;
  Decimal totalInvested = Decimal.zero;
  Decimal unrealisedPnl = Decimal.zero;
  Decimal realisedPnl = Decimal.zero;
  Decimal allTimeDividends = Decimal.zero;
  Decimal currentYearDividends = Decimal.zero;

  final items = <StockSummaryItem>[];

  for (final stock in stocks) {
    final txs = ref.watch(transactionsByStockProvider(stock.id)).value ?? [];
    final splits = ref.watch(splitsByStockProvider(stock.id)).value ?? [];
    final dividends = ref.watch(dividendsByStockProvider(stock.id)).value ?? [];
    final quote = quotes[stock.id];
    final rawQuotePrice = quote?.price ?? Decimal.zero;
    final quoteCurrency = quote?.currency ?? stock.currency;

    // Convert price from quoteCurrency to stock.currency so PnlCalculator
    // sees values in the same unit as stored transaction prices.
    final priceAdjRate = ExchangeRate.find(rates, quoteCurrency, stock.currency);
    final currentPrice = (quote != null && quoteCurrency != stock.currency && priceAdjRate != null)
        ? priceAdjRate.convert(rawQuotePrice)
        : rawQuotePrice;

    final pos = PortfolioCalculator.calculate(txs, splits);
    final pnl = PnlCalculator.calculate(
      transactions: txs,
      splits: splits,
      currentPrice: currentPrice,
    );
    final divSummary = DividendCalculator.calculate(
      paidDividends: dividends
          .where((d) => d.type == DividendType.paid && d.confirmed)
          .toList(),
      currentPrice: currentPrice,
      sharesHeld: pos.sharesHeld,
    );

    // Convert from stock.currency to preferred.
    final rate = ExchangeRate.find(rates, stock.currency, preferred);
    final priceRateMissing = quoteCurrency != stock.currency && priceAdjRate == null;
    final missingRate = priceRateMissing || (stock.currency != preferred && rate == null);
    final convertedPnl = rate != null ? PnlCalculator.convert(pnl, rate) : pnl;
    final convertedDiv = rate != null
        ? DividendCalculator.convert(divSummary, rate)
        : divSummary;

    totalValue = totalValue + convertedPnl.currentValue;
    totalInvested = totalInvested + convertedPnl.totalInvested;
    unrealisedPnl = unrealisedPnl + convertedPnl.unrealisedPnl;
    realisedPnl = realisedPnl + convertedPnl.realisedPnl;
    allTimeDividends = allTimeDividends + convertedDiv.allTimeTotal;
    currentYearDividends = currentYearDividends + convertedDiv.currentYearTotal;

    items.add(StockSummaryItem(
      stock: stock,
      broker: brokerById[stock.brokerId],
      sharesHeld: pos.sharesHeld,
      avgBuyPrice: pos.avgBuyPrice,
      currentPrice: currentPrice,
      rawQuotePrice: rawQuotePrice,
      quoteCurrency: quoteCurrency,
      preferredCurrency: preferred,
      currentValue: convertedPnl.currentValue,
      unrealisedPnl: convertedPnl.unrealisedPnl,
      unrealisedPnlPct: pnl.unrealisedPnlPct,
      annualYieldPct: divSummary.annualYieldPct,
      isStale: quote?.withStaleness().isStale ?? true,
      hasPrice: quote != null,
      missingRate: missingRate,
    ));
  }

  final unrealisedPct = totalInvested == Decimal.zero
      ? Decimal.zero
      : (unrealisedPnl.toRational() /
              totalInvested.toRational() *
              Decimal.fromInt(100).toRational())
          .toDecimal(scaleOnInfinitePrecision: 4);

  return PortfolioSummary(
    totalValue: totalValue,
    totalInvested: totalInvested,
    unrealisedPnl: unrealisedPnl,
    unrealisedPnlPct: unrealisedPct,
    realisedPnl: realisedPnl,
    allTimeDividends: allTimeDividends,
    currentYearDividends: currentYearDividends,
    currency: preferred,
    stockItems: items,
  );
}

