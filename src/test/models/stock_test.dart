import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_manager/core/models/asset_type.dart';
import 'package:stock_manager/core/models/stock.dart';

Stock _stock({
  Decimal? trailingStopPct,
  Decimal? trailingStopHighWater,
  Decimal? manualYieldPct,
}) =>
    Stock(
      id: 'id1',
      brokerId: 'b1',
      isin: 'US0000000001',
      symbol: 'TST',
      name: 'Test Corp',
      exchange: 'NYSE',
      currency: 'USD',
      dripEnabled: false,
      trailingStopPct: trailingStopPct,
      trailingStopHighWater: trailingStopHighWater,
      manualYieldPct: manualYieldPct,
    );

void main() {
  group('Stock.copyWith — manualYieldPct', () {
    test('sets a new value', () {
      final s = _stock();
      final updated = s.copyWith(manualYieldPct: Decimal.parse('6.36'));
      expect(updated.manualYieldPct, Decimal.parse('6.36'));
    });

    test('omitting the parameter preserves the existing value', () {
      final s = _stock(manualYieldPct: Decimal.parse('4'));
      final updated = s.copyWith(symbol: 'TST2');
      expect(updated.manualYieldPct, Decimal.parse('4'));
    });

    test('passing null clears the value', () {
      final s = _stock(manualYieldPct: Decimal.parse('4'));
      final updated = s.copyWith(manualYieldPct: null);
      expect(updated.manualYieldPct, isNull);
    });

    test('other fields are unchanged when only manualYieldPct is updated', () {
      final s = _stock();
      final updated = s.copyWith(manualYieldPct: Decimal.parse('3'));
      expect(updated.id, s.id);
      expect(updated.symbol, s.symbol);
      expect(updated.currency, s.currency);
      expect(updated.dripEnabled, s.dripEnabled);
    });
  });

  group('Stock.copyWith — trailingStopPct sentinel behaviour', () {
    test('omitting trailingStopPct preserves existing value', () {
      final s = _stock(trailingStopPct: Decimal.fromInt(10));
      expect(s.copyWith(symbol: 'X').trailingStopPct, Decimal.fromInt(10));
    });

    test('passing null explicitly clears trailingStopPct', () {
      final s = _stock(trailingStopPct: Decimal.fromInt(10));
      expect(s.copyWith(trailingStopPct: null).trailingStopPct, isNull);
    });
  });

  group('Stock equality (Equatable)', () {
    test('two identical stocks are equal', () {
      final a = _stock(manualYieldPct: Decimal.parse('5'));
      final b = _stock(manualYieldPct: Decimal.parse('5'));
      expect(a, equals(b));
    });

    test('stocks differ when manualYieldPct differs', () {
      final a = _stock(manualYieldPct: Decimal.parse('5'));
      final b = _stock(manualYieldPct: Decimal.parse('6'));
      expect(a, isNot(equals(b)));
    });

    test('stock with manualYieldPct differs from one without', () {
      final a = _stock(manualYieldPct: Decimal.parse('5'));
      final b = _stock();
      expect(a, isNot(equals(b)));
    });

    test('assetType default is AssetType.stock', () {
      expect(_stock().assetType, AssetType.stock);
    });
  });
}
