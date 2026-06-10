import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/brokers_table.dart';
import '../tables/price_cache_table.dart';
import '../tables/stock_splits_table.dart';
import '../tables/stocks_table.dart';

part 'stocks_dao.g.dart';

@DriftAccessor(tables: [Stocks, Brokers, PriceCache, StockSplits])
class StocksDao extends DatabaseAccessor<AppDatabase> with _$StocksDaoMixin {
  StocksDao(super.db);

  Stream<List<StockRow>> watchAll() =>
      (select(stocks)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Future<List<StockRow>> getAll() =>
      (select(stocks)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  Future<List<StockRow>> getByBroker(String brokerId) =>
      (select(stocks)..where((t) => t.brokerId.equals(brokerId))).get();

  Future<StockRow?> findById(String id) =>
      (select(stocks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<StockRow?> watchById(String id) =>
      (select(stocks)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<StockRow?> findByIsin(String isin) =>
      (select(stocks)..where((t) => t.isin.equals(isin))).getSingleOrNull();

  Future<void> upsert(StocksCompanion companion) =>
      into(stocks).insertOnConflictUpdate(companion);

  // Partial UPDATE used by edit-stock — omits broker_id so SQLite does not
  // re-check the FK constraint when broker_id is stale (e.g. after a restore).
  Future<void> updateDetails(StocksCompanion companion) =>
      (update(stocks)..where((t) => t.id.equals(companion.id.value)))
          .write(companion);

  Future<int> deleteById(String id) =>
      (delete(stocks)..where((t) => t.id.equals(id))).go();

  Stream<List<StockSplitRow>> watchSplitsForStock(String stockId) =>
      (select(stockSplits)
            ..where((t) => t.stockId.equals(stockId))
            ..orderBy([(t) => OrderingTerm.asc(t.date)]))
          .watch();

  Future<List<StockSplitRow>> getSplitsForStock(String stockId) =>
      (select(stockSplits)
            ..where((t) => t.stockId.equals(stockId))
            ..orderBy([(t) => OrderingTerm.asc(t.date)]))
          .get();

  Future<List<StockSplitRow>> getAllSplits() => select(stockSplits).get();

  Future<void> upsertSplit(StockSplitsCompanion companion) =>
      into(stockSplits).insertOnConflictUpdate(companion);

  Future<int> deleteSplit(String splitId) =>
      (delete(stockSplits)..where((t) => t.id.equals(splitId))).go();

  // Price cache
  Future<PriceCacheRow?> getCachedPrice(String stockId) =>
      (select(priceCache)..where((t) => t.stockId.equals(stockId)))
          .getSingleOrNull();

  Future<Map<String, PriceCacheRow>> getAllCachedPrices() async {
    final rows = await select(priceCache).get();
    return {for (final r in rows) r.stockId: r};
  }

  Future<List<PriceCacheRow>> getManualPrices() =>
      (select(priceCache)..where((t) => t.manualOverride.equals(true))).get();

  Future<void> upsertPrice(PriceCacheCompanion companion) =>
      into(priceCache).insertOnConflictUpdate(companion);

  Future<int> deletePrice(String stockId) =>
      (delete(priceCache)..where((t) => t.stockId.equals(stockId))).go();

  Future<void> updateLastKnownConsensus(String stockId, String? consensus) =>
      (update(stocks)..where((t) => t.id.equals(stockId)))
          .write(StocksCompanion(lastKnownConsensus: Value(consensus)));

  Future<void> updateTrailingStop(
          String stockId, String? pct, String? highWater) =>
      (update(stocks)..where((t) => t.id.equals(stockId))).write(
        StocksCompanion(
          trailingStopPct: Value(pct),
          trailingStopHighWater: Value(highWater),
        ),
      );

  Future<void> updateTrailingStopHighWater(String stockId, String? highWater) =>
      (update(stocks)..where((t) => t.id.equals(stockId))).write(
        StocksCompanion(trailingStopHighWater: Value(highWater)),
      );

  Future<int> count() async {
    final result = await customSelect(
      'SELECT COUNT(*) AS c FROM stocks',
      readsFrom: {stocks},
    ).getSingle();
    return result.read<int>('c');
  }
}
