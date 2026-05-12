import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/transactions_table.dart';

part 'transactions_dao.g.dart';

@DriftAccessor(tables: [Transactions])
class TransactionsDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionsDaoMixin {
  TransactionsDao(super.db);

  Stream<List<TransactionRow>> watchByStock(String stockId) =>
      (select(transactions)
            ..where((t) => t.stockId.equals(stockId))
            ..orderBy([(t) => OrderingTerm.asc(t.executedAt)]))
          .watch();

  Future<List<TransactionRow>> getByStock(String stockId) =>
      (select(transactions)
            ..where((t) => t.stockId.equals(stockId))
            ..orderBy([(t) => OrderingTerm.asc(t.executedAt)]))
          .get();

  Future<List<TransactionRow>> getAll() =>
      (select(transactions)
            ..orderBy([(t) => OrderingTerm.desc(t.executedAt)]))
          .get();

  Future<TransactionRow?> findById(String id) =>
      (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insert(TransactionsCompanion companion) =>
      into(transactions).insert(companion);

  Future<bool> update(TransactionsCompanion companion) =>
      (update(transactions)
            ..where((t) => t.id.equals(companion.id.value)))
          .write(companion)
          .then((count) => count > 0);

  Future<int> deleteById(String id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();
}
