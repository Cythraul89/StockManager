import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_manager/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertBrokerAndStock(String stockId) async {
    await db.brokersDao.upsert(
      BrokersCompanion.insert(id: 'b1', name: 'Test Broker'),
    );
    await db.stocksDao.upsert(
      StocksCompanion.insert(
        id: stockId,
        brokerId: 'b1',
        isin: 'US0231351067',
        symbol: 'AAPL',
        name: 'Apple Inc.',
        exchange: 'NASDAQ',
        currency: 'USD',
      ),
    );
  }

  group('StocksDao — trailing stop', () {
    test('updateTrailingStop sets pct and highWater', () async {
      await insertBrokerAndStock('s1');
      await db.stocksDao.updateTrailingStop('s1', '10', '150.00');

      final row = await db.stocksDao.findById('s1');
      expect(row, isNotNull);
      expect(row!.trailingStopPct, '10');
      expect(row.trailingStopHighWater, '150.00');
    });

    test('updateTrailingStop with null clears both fields', () async {
      await insertBrokerAndStock('s2');
      await db.stocksDao.updateTrailingStop('s2', '10', '150.00');
      await db.stocksDao.updateTrailingStop('s2', null, null);

      final row = await db.stocksDao.findById('s2');
      expect(row!.trailingStopPct, isNull);
      expect(row.trailingStopHighWater, isNull);
    });

    test('updateTrailingStopHighWater updates only the high-water mark', () async {
      await insertBrokerAndStock('s3');
      await db.stocksDao.updateTrailingStop('s3', '15', '200.00');
      await db.stocksDao.updateTrailingStopHighWater('s3', '210.00');

      final row = await db.stocksDao.findById('s3');
      expect(row!.trailingStopPct, '15'); // unchanged
      expect(row.trailingStopHighWater, '210.00');
    });

    test('updateTrailingStopHighWater can reset high-water to null', () async {
      await insertBrokerAndStock('s4');
      await db.stocksDao.updateTrailingStop('s4', '10', '180.00');
      await db.stocksDao.updateTrailingStopHighWater('s4', null);

      final row = await db.stocksDao.findById('s4');
      expect(row!.trailingStopPct, '10'); // pct preserved
      expect(row.trailingStopHighWater, isNull);
    });

    test('new stock has null trailing stop fields by default', () async {
      await insertBrokerAndStock('s5');

      final row = await db.stocksDao.findById('s5');
      expect(row!.trailingStopPct, isNull);
      expect(row.trailingStopHighWater, isNull);
    });
  });
}
