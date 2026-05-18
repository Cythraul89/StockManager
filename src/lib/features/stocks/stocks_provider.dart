import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/calculators/portfolio_calculator.dart';
import '../../core/database/app_database.dart';
import '../../core/models/analyst_data.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/broker.dart';
import '../../core/models/chart_range.dart';
import '../../core/models/dividend.dart';
import '../../core/models/fetched_dividend.dart';
import '../../core/models/news_article.dart';
import '../../core/models/price_point.dart';
import '../../core/models/price_quote.dart';
import '../../core/models/asset_type.dart';
import '../../core/models/stock.dart';
import '../../core/models/stock_split.dart';
import '../../core/models/transaction.dart';
import '../../core/services/isin_lookup_service.dart';
import '../../core/services/market_data_service.dart';
import '../../core/utils/withholding_tax.dart';
import '../settings/settings_provider.dart';

final isinLookupServiceProvider = Provider<IsinLookupService>((ref) {
  throw UnimplementedError('isinLookupServiceProvider must be overridden');
});

// ── Database provider ──────────────────────────────────────────────────────────────────────────

final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden in ProviderScope');
});

// ── Broker providers ────────────────────────────────────────────────────────────────────────

final brokersProvider = FutureProvider<List<Broker>>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.brokersDao.getAll();
  return rows.map(_brokerFromRow).toList();
});

final brokersStreamProvider = StreamProvider<List<Broker>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.brokersDao.watchAll().map((rows) => rows.map(_brokerFromRow).toList());
});

// ── Stock providers ───────────────────────────────────────────────────────────────────────────

final stocksProvider = FutureProvider<List<Stock>>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.stocksDao.getAll();
  return rows.map(_stockFromRow).toList();
});

final stocksStreamProvider = StreamProvider<List<Stock>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.stocksDao.watchAll().map((rows) => rows.map(_stockFromRow).toList());
});

final stockByIdProvider =
    StreamProvider.family<Stock?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return db.stocksDao
      .watchById(id)
      .map((row) => row == null ? null : _stockFromRow(row));
});

// ── Transaction providers ──────────────────────────────────────────────────────────────────

final transactionsByStockProvider =
    StreamProvider.family<List<StockTransaction>, String>((ref, stockId) {
  final db = ref.watch(databaseProvider);
  return db.transactionsDao
      .watchByStock(stockId)
      .map((rows) => rows.map(_txFromRow).toList());
});

// ── Split providers ────────────────────────────────────────────────────────────────────────────

final splitsByStockProvider =
    StreamProvider.family<List<StockSplit>, String>((ref, stockId) {
  final db = ref.watch(databaseProvider);
  return db.stocksDao
      .watchSplitsForStock(stockId)
      .map((rows) => rows.map(_splitFromRow).toList());
});

// ── Dividend providers ───────────────────────────────────────────────────────────────────────

final dividendsByStockProvider =
    StreamProvider.family<List<Dividend>, String>((ref, stockId) {
  final db = ref.watch(databaseProvider);
  return db.dividendsDao
      .watchByStock(stockId)
      .map((rows) => rows.map(_dividendFromRow).toList());
});

final allDividendsProvider = FutureProvider<List<Dividend>>((ref) async {
  ref.watch(dataVersionProvider); // Refresh on any data mutation
  final db = ref.watch(databaseProvider);
  final rows = await db.dividendsDao.getAll();
  return rows.map(_dividendFromRow).toList();
});

// ── Analyst data (fetched on demand, keyed by stockId) ───────────────────────────

// Incrementing this counter forces analystDataProvider to re-fetch.
// Using a StateProvider rather than ref.invalidate avoids interference with
// the keepAlive link inside the FutureProvider.
final analystRefreshProvider =
    StateProvider.family<int, String>((ref, stockId) => 0);

final analystDataProvider =
    FutureProvider.family<AnalystData?, String>((ref, stockId) async {
  // Re-run whenever the manual refresh counter is incremented.
  ref.watch(analystRefreshProvider(stockId));
  ref.watch(analystCacheVersionProvider); // busts cache on provider/key change

  // Keep the result alive for 10 minutes so navigating away and back does not
  // trigger a full Yahoo Finance round-trip on every visit.
  final link = ref.keepAlive();
  Timer(const Duration(minutes: 10), link.close);

  final stock = await ref.watch(stockByIdProvider(stockId).future);
  if (stock == null) return null;

  final settings = await ref.watch(settingsProvider.future);
  if (settings.marketDataProvider == MarketDataProvider.finnhub) {
    final apiKey = await ref.watch(finnhubApiKeyProvider.future);
    if (apiKey == null || apiKey.isEmpty) return null;
    return ref
        .read(marketDataServiceProvider)
        .fetchAnalystDataFinnhubWithFallback(stock.symbol, apiKey);
  }

  return ref.read(marketDataServiceProvider).fetchAnalystData(stock.symbol);
});

// ── Price history (fetched on demand, keyed by stockId + range) ──────────────

// Re-fetches automatically when the stock changes (e.g. after a ticker edit)
// because it watches stockByIdProvider directly.
final priceHistoryProvider = FutureProvider.family<List<PricePoint>,
    (String stockId, ChartRange range)>((ref, args) async {
  final (stockId, range) = args;

  // Cache results for 5 minutes so navigating away and back does not trigger
  // a full refetch, especially important for long-range (5Y / MAX) requests.
  final link = ref.keepAlive();
  Timer(const Duration(minutes: 5), link.close);

  final stockAsync = ref.watch(stockByIdProvider(stockId));
  final stock = stockAsync.value;
  if (stock == null) return [];
  return ref
      .read(marketDataServiceProvider)
      .fetchPriceHistory(stock.symbol, range);
});

// ── News (fetched on open, cached 30 min, keyed by stockId) ─────────────────

final newsProvider =
    FutureProvider.family<List<NewsArticle>, String>((ref, stockId) async {
  final stock = await ref.watch(stockByIdProvider(stockId).future);
  if (stock == null) return [];

  final link = ref.keepAlive();
  Timer(const Duration(minutes: 30), link.close);

  final settings = await ref.watch(settingsProvider.future);
  String? finnhubKey;
  if (settings.marketDataProvider == MarketDataProvider.finnhub) {
    finnhubKey = await ref.watch(finnhubApiKeyProvider.future);
  }

  return ref
      .read(marketDataServiceProvider)
      .fetchNews(stock.symbol, finnhubApiKey: finnhubKey);
});

// ── Price quote cache (in-memory, refreshed on demand) ───────────────────────────

final priceQuotesProvider =
    StateProvider<Map<String, PriceQuote>>((ref) => {});

final marketDataServiceProvider = Provider<MarketDataService>((ref) {
  throw UnimplementedError('marketDataServiceProvider must be overridden');
});

// Increments on every data mutation; sync service listens to schedule uploads.
final dataVersionProvider = StateProvider<int>((ref) => 0);

// ── CRUD actions ─────────────────────────────────────────────────────────────────────────────

class StockActions {
  StockActions(this._db, this._ref);
  final AppDatabase _db;
  final Ref _ref;
  static const _uuid = Uuid();

  void _notifyChange() =>
      _ref.read(dataVersionProvider.notifier).update((n) => n + 1);

  Future<String> addStock(Stock stock) async {
    final id = stock.id.isEmpty ? _uuid.v4() : stock.id;
    await _db.stocksDao.upsert(StocksCompanion.insert(
      id: id,
      brokerId: stock.brokerId,
      isin: stock.isin,
      symbol: stock.symbol,
      name: stock.name,
      exchange: stock.exchange,
      currency: stock.currency,
      dripEnabled: Value(stock.dripEnabled),
      assetType: Value(stock.assetType.dbValue),
    ));
    _notifyChange();
    return id;
  }

  Future<void> updateStock(Stock stock) async {
    await _db.stocksDao.upsert(
      StocksCompanion(
        id: Value(stock.id),
        brokerId: Value(stock.brokerId),
        isin: Value(stock.isin),
        symbol: Value(stock.symbol),
        name: Value(stock.name),
        exchange: Value(stock.exchange),
        currency: Value(stock.currency),
        dripEnabled: Value(stock.dripEnabled),
        assetType: Value(stock.assetType.dbValue),
      ),
    );
    _notifyChange();
  }

  Future<void> deleteStock(String stockId) async {
    await _db.stocksDao.deleteById(stockId);
    _notifyChange();
  }

  Future<void> addSplit(StockSplit split) async {
    final id = split.id.isEmpty ? _uuid.v4() : split.id;
    await _db.stocksDao.upsertSplit(StockSplitsCompanion.insert(
      id: id,
      stockId: split.stockId,
      date: split.date,
      fromShares: split.fromShares,
      toShares: split.toShares,
    ));
    _notifyChange();
  }

  Future<void> deleteSplit(String splitId) async {
    await _db.stocksDao.deleteSplit(splitId);
    _notifyChange();
  }

  Future<String> addTransaction(StockTransaction tx) async {
    final id = tx.id.isEmpty ? _uuid.v4() : tx.id;
    await _db.transactionsDao.insert(TransactionsCompanion.insert(
      id: id,
      stockId: tx.stockId,
      type: tx.type.name,
      executedAt: tx.executedAt,
      shares: tx.shares,
      pricePerShare: tx.pricePerShare,
      currency: tx.currency,
      fees: Value(tx.fees),
      notes: Value(tx.notes),
    ));
    _notifyChange();
    return id;
  }

  Future<void> updateTransaction(StockTransaction tx) async {
    await _db.transactionsDao.updateRow(TransactionsCompanion(
      id: Value(tx.id),
      type: Value(tx.type.name),
      executedAt: Value(tx.executedAt),
      shares: Value(tx.shares),
      pricePerShare: Value(tx.pricePerShare),
      fees: Value(tx.fees),
      notes: Value(tx.notes),
    ));
    _notifyChange();
  }

  Future<void> deleteTransaction(String txId) async {
    await _db.transactionsDao.deleteById(txId);
    _notifyChange();
  }

  Future<String> addDividend(Dividend div) async {
    final id = div.id.isEmpty ? _uuid.v4() : div.id;
    await _db.dividendsDao.insert(DividendsCompanion.insert(
      id: id,
      stockId: div.stockId,
      type: div.type.name,
      date: div.date,
      amountPerShare: div.amountPerShare,
      totalAmount: Value(div.totalAmount),
      currency: div.currency,
      withholdingTax: Value(div.withholdingTax),
      notes: Value(div.notes),
      source: Value(div.source.name),
      confirmed: Value(div.confirmed),
    ));
    _notifyChange();
    return id;
  }

  Future<void> updateDividend(Dividend div) async {
    await _db.dividendsDao.updateRow(DividendsCompanion(
      id: Value(div.id),
      type: Value(div.type.name),
      date: Value(div.date),
      amountPerShare: Value(div.amountPerShare),
      totalAmount: Value(div.totalAmount),
      currency: Value(div.currency),
      withholdingTax: Value(div.withholdingTax),
      notes: Value(div.notes),
      confirmed: Value(div.confirmed),
    ));
    _notifyChange();
  }

  Future<void> deleteDividend(String divId) async {
    await _db.dividendsDao.deleteById(divId);
    _notifyChange();
  }

  /// Inserts auto-fetched dividends for dates when shares were actually held,
  /// skipping dates already in the database.  Pre-fills totalAmount from the
  /// share count at the dividend date and withholdingTax from the treaty rate
  /// for the ISIN's source country (both are estimates; user can adjust).
  Future<void> syncDividends(
    String stockId,
    String currency,
    String isin,
    List<FetchedDividend> fetched,
    List<StockTransaction> transactions,
    List<StockSplit> splits,
  ) async {
    final taxRate = withholdingTaxRate(isin);

    for (final d in fetched) {
      final existing =
          await _db.dividendsDao.findByStockAndDate(stockId, d.date);
      if (existing != null) continue;

      // Skip if no shares were held on the dividend date.
      final sharesHeld =
          PortfolioCalculator.sharesAtDate(transactions, splits, d.date);
      if (sharesHeld <= Decimal.zero) continue;

      final type = d.isPaid ? DividendType.paid : DividendType.expected;
      // Paid auto-fetched dividends need user confirmation; expected do not.
      final needsConfirmation = d.isPaid;

      Decimal? totalAmount;
      Decimal? withholdingTax;
      if (d.isPaid) {
        totalAmount = d.amountPerShare * sharesHeld;
        if (taxRate > Decimal.zero) {
          withholdingTax =
              (totalAmount.toRational() * taxRate.toRational())
                  .toDecimal(scaleOnInfinitePrecision: 4);
        }
      }

      await _db.dividendsDao.insert(DividendsCompanion.insert(
        id: _uuid.v4(),
        stockId: stockId,
        type: type.name,
        date: d.date,
        amountPerShare: d.amountPerShare,
        totalAmount: Value(totalAmount),
        currency: currency,
        withholdingTax: Value(withholdingTax),
        source: const Value('auto'),
        confirmed: Value(!needsConfirmation),
      ));
    }
    _notifyChange();
  }

  /// Marks a pending auto-fetched paid dividend as confirmed with user-adjusted values.
  Future<void> confirmDividend(Dividend div) async {
    await _db.dividendsDao.updateRow(DividendsCompanion(
      id: Value(div.id),
      type: Value(div.type.name),
      date: Value(div.date),
      amountPerShare: Value(div.amountPerShare),
      totalAmount: Value(div.totalAmount),
      currency: Value(div.currency),
      withholdingTax: Value(div.withholdingTax),
      notes: Value(div.notes),
      confirmed: const Value(true),
    ));
    _notifyChange();
  }

  Future<void> setManualPrice(
      String stockId, Decimal price, String currency) async {
    await _db.stocksDao.upsertPrice(PriceCacheCompanion.insert(
      stockId: stockId,
      price: price,
      currency: currency,
      fetchedAt: DateTime.now(),
      manualOverride: const Value(true),
    ));
    _notifyChange();
  }

  Future<void> clearManualPrice(String stockId) async {
    await _db.stocksDao.deletePrice(stockId);
    _notifyChange();
  }

  Future<void> cacheMarketPrice(PriceQuote quote) async {
    await _db.stocksDao.upsertPrice(PriceCacheCompanion.insert(
      stockId: quote.stockId,
      price: quote.price,
      currency: quote.currency,
      fetchedAt: quote.fetchedAt,
      manualOverride: const Value(false),
    ));
  }

  Future<Map<String, PriceQuote>> loadManualPrices() async {
    final rows = await _db.stocksDao.getManualPrices();
    return {
      for (final r in rows)
        r.stockId: PriceQuote(
          stockId: r.stockId,
          price: r.price,
          currency: r.currency,
          fetchedAt: r.fetchedAt,
          isManualOverride: true,
        ),
    };
  }
}

final stockActionsProvider = Provider<StockActions>((ref) {
  return StockActions(ref.watch(databaseProvider), ref);
});

// ── Row → model mappers ─────────────────────────────────────────────────────────────────────────

Broker _brokerFromRow(BrokerRow r) =>
    Broker(id: r.id, name: r.name, notes: r.notes);

Stock _stockFromRow(StockRow r) => Stock(
      id: r.id,
      brokerId: r.brokerId,
      isin: r.isin,
      symbol: r.symbol,
      name: r.name,
      exchange: r.exchange,
      currency: r.currency,
      dripEnabled: r.dripEnabled,
      assetType: AssetType.fromDb(r.assetType),
    );

StockTransaction _txFromRow(TransactionRow r) => StockTransaction(
      id: r.id,
      stockId: r.stockId,
      type: TransactionType.values.byName(r.type),
      executedAt: r.executedAt,
      shares: r.shares,
      pricePerShare: r.pricePerShare,
      currency: r.currency,
      fees: r.fees,
      notes: r.notes,
    );

StockSplit _splitFromRow(StockSplitRow r) => StockSplit(
      id: r.id,
      stockId: r.stockId,
      date: r.date,
      fromShares: r.fromShares,
      toShares: r.toShares,
    );

Dividend _dividendFromRow(DividendRow r) => Dividend(
      id: r.id,
      stockId: r.stockId,
      type: DividendType.values.byName(r.type),
      date: r.date,
      amountPerShare: r.amountPerShare,
      totalAmount: r.totalAmount,
      currency: r.currency,
      withholdingTax: r.withholdingTax,
      notes: r.notes,
      source: DividendSource.values.byName(r.source),
      confirmed: r.confirmed,
    );
