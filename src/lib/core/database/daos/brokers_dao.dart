import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/brokers_table.dart';

part 'brokers_dao.g.dart';

@DriftAccessor(tables: [Brokers])
class BrokersDao extends DatabaseAccessor<AppDatabase>
    with _$BrokersDaoMixin {
  BrokersDao(super.db);

  Stream<List<BrokerRow>> watchAll() =>
      (select(brokers)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Future<List<BrokerRow>> getAll() =>
      (select(brokers)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  Future<BrokerRow?> findById(String id) =>
      (select(brokers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(BrokersCompanion companion) =>
      into(brokers).insertOnConflictUpdate(companion);

  Future<int> deleteById(String id) =>
      (delete(brokers)..where((t) => t.id.equals(id))).go();

  Future<int> count() async {
    final result = await customSelect(
      'SELECT COUNT(*) AS c FROM brokers',
      readsFrom: {brokers},
    ).getSingle();
    return result.read<int>('c');
  }
}
