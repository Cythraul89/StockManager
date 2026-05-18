import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/brokers_dao.dart';
import 'daos/dividends_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/stocks_dao.dart';
import 'daos/transactions_dao.dart';
import 'tables/brokers_table.dart';
import 'tables/decimal_converter.dart';
import 'tables/dividends_table.dart';
import 'tables/exchange_rate_cache_table.dart';
import 'tables/price_cache_table.dart';
import 'tables/settings_table.dart';
import 'tables/stock_splits_table.dart';
import 'tables/stocks_table.dart';
import 'tables/transactions_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Brokers,
    Stocks,
    Transactions,
    StockSplits,
    Dividends,
    PriceCache,
    ExchangeRateCache,
    Settings,
  ],
  daos: [
    BrokersDao,
    StocksDao,
    TransactionsDao,
    DividendsDao,
    SettingsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(priceCache, priceCache.manualOverride);
          }
          if (from < 3) {
            await m.addColumn(dividends, dividends.source);
            await m.addColumn(dividends, dividends.confirmed);
          }
          if (from < 4) {
            await m.addColumn(settings, settings.sparklineRange);
          }
          if (from < 5) {
            await m.addColumn(settings, settings.marketDataProvider);
          }
          if (from < 6) {
            await m.addColumn(stocks, stocks.assetType);
          }
          if (from < 7) {
            await m.addColumn(settings, settings.nextcloudPassword);
            await m.addColumn(settings, settings.finnhubApiKey);
          }
          if (from < 8) {
            await m.addColumn(settings, settings.nextcloudCertFingerprint);
          }
          if (from < 9) {
            await m.addColumn(stocks, stocks.lastKnownConsensus);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'stock_manager.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
