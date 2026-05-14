import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/exchange_rate_cache_table.dart';
import '../tables/settings_table.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [Settings, ExchangeRateCache])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  static const _settingsId = 1;

  Stream<SettingsRow?> watchSettings() =>
      (select(settings)..where((t) => t.id.equals(_settingsId)))
          .watchSingleOrNull();

  Future<SettingsRow?> getSettings() =>
      (select(settings)..where((t) => t.id.equals(_settingsId)))
          .getSingleOrNull();

  Future<void> upsertSettings(SettingsCompanion companion) =>
      into(settings).insertOnConflictUpdate(
        companion.copyWith(id: const Value(_settingsId)),
      );

  Future<void> updateLastSyncAt(DateTime time) =>
      (update(settings)..where((t) => t.id.equals(_settingsId)))
          .write(SettingsCompanion(lastSyncAt: Value(time)));

  // Exchange rates
  Stream<List<ExchangeRateCacheRow>> watchExchangeRates() =>
      (select(exchangeRateCache)
            ..orderBy([(t) => OrderingTerm.asc(t.base)]))
          .watch();

  Future<List<ExchangeRateCacheRow>> getExchangeRates() =>
      select(exchangeRateCache).get();

  Future<ExchangeRateCacheRow?> getRate(String base, String target) =>
      (select(exchangeRateCache)
            ..where((t) => t.base.equals(base) & t.target.equals(target)))
          .getSingleOrNull();

  Future<void> upsertRate(ExchangeRateCacheCompanion companion) =>
      into(exchangeRateCache).insertOnConflictUpdate(companion);

  Future<int> deleteRate(String base, String target) =>
      (delete(exchangeRateCache)
            ..where((t) => t.base.equals(base) & t.target.equals(target)))
          .go();
}
