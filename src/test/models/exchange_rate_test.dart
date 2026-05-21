import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_manager/core/models/exchange_rate.dart';

ExchangeRate _rate({
  required String base,
  required String target,
  required String rate,
  bool manual = false,
  Duration age = Duration.zero,
}) =>
    ExchangeRate(
      base: base,
      target: target,
      rate: Decimal.parse(rate),
      fetchedAt: DateTime.now().subtract(age),
      isManualOverride: manual,
    );

void main() {
  group('ExchangeRate.find', () {
    test('finds matching rate (base==to, target==from)', () {
      final rates = [
        _rate(base: 'EUR', target: 'USD', rate: '0.9'),
      ];
      final found = ExchangeRate.find(rates, 'USD', 'EUR');
      expect(found, isNotNull);
      expect(found!.rate, Decimal.parse('0.9'));
    });

    test('returns null when from == to', () {
      final rates = [_rate(base: 'USD', target: 'USD', rate: '1')];
      expect(ExchangeRate.find(rates, 'USD', 'USD'), isNull);
    });

    test('returns null when no matching rate exists', () {
      final rates = [_rate(base: 'EUR', target: 'USD', rate: '0.9')];
      expect(ExchangeRate.find(rates, 'GBP', 'EUR'), isNull);
    });

    test('returns first match in list', () {
      final rates = [
        _rate(base: 'EUR', target: 'USD', rate: '0.9'),
        _rate(base: 'EUR', target: 'USD', rate: '0.85'),
      ];
      final found = ExchangeRate.find(rates, 'USD', 'EUR');
      expect(found!.rate, Decimal.parse('0.9'));
    });
  });

  group('ExchangeRate.convert', () {
    test('multiplies amount by rate', () {
      final r = _rate(base: 'EUR', target: 'USD', rate: '0.9');
      expect(r.convert(Decimal.fromInt(100)), Decimal.parse('90'));
    });

    test('converts zero to zero', () {
      final r = _rate(base: 'EUR', target: 'USD', rate: '0.9');
      expect(r.convert(Decimal.zero), Decimal.zero);
    });

    test('negative amount is preserved in sign', () {
      final r = _rate(base: 'EUR', target: 'USD', rate: '0.9');
      expect(r.convert(Decimal.parse('-100')), Decimal.parse('-90'));
    });
  });

  group('ExchangeRate.isStale', () {
    test('manual override is never stale', () {
      final r = _rate(
        base: 'EUR',
        target: 'USD',
        rate: '0.9',
        manual: true,
        age: const Duration(days: 2),
      );
      expect(r.isStale, isFalse);
    });

    test('live rate older than 1 hour is stale', () {
      final r = _rate(
        base: 'EUR',
        target: 'USD',
        rate: '0.9',
        age: const Duration(hours: 2),
      );
      expect(r.isStale, isTrue);
    });

    test('live rate fetched moments ago is not stale', () {
      final r = _rate(
        base: 'EUR',
        target: 'USD',
        rate: '0.9',
        age: const Duration(minutes: 5),
      );
      expect(r.isStale, isFalse);
    });
  });

  group('ExchangeRate equality (Equatable)', () {
    test('two rates with same fields are equal', () {
      final fetchedAt = DateTime(2024, 1, 1);
      final a = ExchangeRate(
        base: 'EUR',
        target: 'USD',
        rate: Decimal.parse('0.9'),
        fetchedAt: fetchedAt,
        isManualOverride: false,
      );
      final b = ExchangeRate(
        base: 'EUR',
        target: 'USD',
        rate: Decimal.parse('0.9'),
        fetchedAt: fetchedAt,
        isManualOverride: false,
      );
      expect(a, equals(b));
    });

    test('rates with different values are not equal', () {
      final fetchedAt = DateTime(2024, 1, 1);
      final a = ExchangeRate(
        base: 'EUR',
        target: 'USD',
        rate: Decimal.parse('0.9'),
        fetchedAt: fetchedAt,
        isManualOverride: false,
      );
      final b = ExchangeRate(
        base: 'EUR',
        target: 'USD',
        rate: Decimal.parse('0.85'),
        fetchedAt: fetchedAt,
        isManualOverride: false,
      );
      expect(a, isNot(equals(b)));
    });
  });
}
