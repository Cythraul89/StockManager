import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_manager/core/utils/decimal_math.dart';

void main() {
  group('DecimalX — predicates', () {
    test('isZero', () {
      expect(Decimal.zero.isZero, isTrue);
      expect(Decimal.one.isZero, isFalse);
      expect(Decimal.parse('-1').isZero, isFalse);
    });

    test('isPositive', () {
      expect(Decimal.one.isPositive, isTrue);
      expect(Decimal.zero.isPositive, isFalse);
      expect(Decimal.parse('-1').isPositive, isFalse);
    });

    test('isNegative', () {
      expect(Decimal.parse('-1').isNegative, isTrue);
      expect(Decimal.zero.isNegative, isFalse);
      expect(Decimal.one.isNegative, isFalse);
    });
  });

  group('DecimalX.percentChangeFrom', () {
    test('50% gain: 150 from base 100', () {
      final result = Decimal.fromInt(150).percentChangeFrom(Decimal.fromInt(100));
      expect(result, Decimal.fromInt(50));
    });

    test('50% loss: 50 from base 100', () {
      final result = Decimal.fromInt(50).percentChangeFrom(Decimal.fromInt(100));
      expect(result, Decimal.fromInt(-50));
    });

    test('zero base returns zero (no division by zero)', () {
      final result = Decimal.fromInt(100).percentChangeFrom(Decimal.zero);
      expect(result, Decimal.zero);
    });

    test('no change returns 0%', () {
      final result = Decimal.fromInt(100).percentChangeFrom(Decimal.fromInt(100));
      expect(result, Decimal.zero);
    });
  });

  group('DecimalMath.weightedAverage', () {
    test('single item returns its value', () {
      final result = DecimalMath.weightedAverage([
        (value: Decimal.fromInt(50), weight: Decimal.fromInt(10)),
      ]);
      expect(result, Decimal.fromInt(50));
    });

    test('equal weights → simple average', () {
      final result = DecimalMath.weightedAverage([
        (value: Decimal.fromInt(100), weight: Decimal.fromInt(1)),
        (value: Decimal.fromInt(200), weight: Decimal.fromInt(1)),
      ]);
      expect(result, Decimal.fromInt(150));
    });

    test('unequal weights bias toward heavier item', () {
      // 100 × 1 + 200 × 3 = 700; total weight = 4; avg = 175
      final result = DecimalMath.weightedAverage([
        (value: Decimal.fromInt(100), weight: Decimal.fromInt(1)),
        (value: Decimal.fromInt(200), weight: Decimal.fromInt(3)),
      ]);
      expect(result, Decimal.fromInt(175));
    });

    test('empty list returns zero', () {
      expect(DecimalMath.weightedAverage([]), Decimal.zero);
    });

    test('zero total weight returns zero', () {
      final result = DecimalMath.weightedAverage([
        (value: Decimal.fromInt(100), weight: Decimal.zero),
      ]);
      expect(result, Decimal.zero);
    });
  });

  group('DecimalMath.clampMin', () {
    test('positive value is unchanged', () {
      expect(DecimalMath.clampMin(Decimal.parse('5.5')), Decimal.parse('5.5'));
    });

    test('zero is unchanged', () {
      expect(DecimalMath.clampMin(Decimal.zero), Decimal.zero);
    });

    test('negative value is clamped to zero', () {
      expect(DecimalMath.clampMin(Decimal.parse('-3')), Decimal.zero);
    });
  });
}
