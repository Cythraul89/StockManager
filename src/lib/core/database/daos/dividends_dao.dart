import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/dividends_table.dart';

part 'dividends_dao.g.dart';

@DriftAccessor(tables: [Dividends])
class DividendsDao extends DatabaseAccessor<AppDatabase>
    with _$DividendsDaoMixin {
  DividendsDao(super.db);

  Stream<List<DividendRow>> watchByStock(String stockId) =>
      (select(dividends)
            ..where((t) => t.stockId.equals(stockId))
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .watch();

  Future<List<DividendRow>> getByStock(String stockId) =>
      (select(dividends)
            ..where((t) => t.stockId.equals(stockId))
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .get();

  Future<List<DividendRow>> getPaid() =>
      (select(dividends)
            ..where((t) => t.type.equals('paid'))
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .get();

  Future<List<DividendRow>> getExpected() =>
      (select(dividends)
            ..where((t) => t.type.equals('expected'))
            ..orderBy([(t) => OrderingTerm.asc(t.date)]))
          .get();

  Future<List<DividendRow>> getAll() =>
      (select(dividends)..orderBy([(t) => OrderingTerm.desc(t.date)])).get();

  Future<void> insert(DividendsCompanion companion) =>
      into(dividends).insert(companion);

  Future<bool> updateRow(DividendsCompanion companion) =>
      (update(dividends)..where((t) => t.id.equals(companion.id.value)))
          .write(companion)
          .then((count) => count > 0);

  Future<int> deleteById(String id) =>
      (delete(dividends)..where((t) => t.id.equals(id))).go();
}
