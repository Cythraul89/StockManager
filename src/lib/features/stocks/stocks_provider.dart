import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/models/broker.dart';
import '../../core/models/dividend.dart';
import '../../core/models/price_quote.dart';
import '../../core/models/stock.dart';
import '../../core/models/stock_split.dart';
import '../../core/models/transaction.dart';
import '../../core/services/market_data_service.dart';

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
    FutureProvider.family<Stock?, String>((ref, id) async {
  final db = ref.watch(databaseProvider);
  final row = await db.stocksDao.findById(id);
  return row == null ? null : _stockFromRow(row);
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
    FutureProvider.family<List<StockSplit>, String>((ref, stockId) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.stocksDao.getSplitsForStock(stockId);
  return rows.map(_splitFromRow).toList();
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
  final db = ref.watch(databaseProvider);
  final rows = await db.dividendsDao.getAll();
  return rows.map(_dividendFromRow).toList();
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
  static final _uuid = Uuid();

  void _notifyChange() =>
      _ref.read(dataVersionProvider.notifier).update((n) => n + 1);

  Future<String> addStock(Stock stock) async {
    await _db.stocksDao.upsert(StocksCompanion.insert(
      id: stock.id.isEmpty ? _uuid.v4() : stock.id,
      brokerId: stock.brokerId,
      isin: stock.isin,
      symbol: stock.symbol,
      name: stock.name,
      exchange: stock.exchange,
      currency: stock.currency,
      dripEnabled: Value(stock.dripEnabled),
    ));
    _notifyChange();
    return stock.id;
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
      ),
    );
    _notifyChange();
  }

  Future<void> deleteStock(String stockId) async {
    await _db.stocksDao.deleteById(stockId);
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
    ));
    _notifyChange();
    return id;
  }

  Future<void> deleteDividend(String divId) async {
    await _db.dividendsDao.deleteById(divId);
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
    );
