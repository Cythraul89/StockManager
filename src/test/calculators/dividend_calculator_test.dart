import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_manager/core/calculators/dividend_calculator.dart';
import 'package:stock_manager/core/models/dividend.dart';
import 'package:stock_manager/core/models/exchange_rate.dart';

Dividend _paid({
  required String id,
  required DateTime date,
  required String total,
  String? withholding,
}) =>
    Dividend(
      id: id,
      stockId: 's1',
      type: DividendType.paid,
      date: date,
      amountPerShare: Decimal.parse('1'),
      totalAmount: Decimal.parse(total),
      currency: 'USD',
      withholdingTax:
          withholding != null ? Decimal.parse(withholding) : null,
    );

void main() {
  group('DividendCalculator.estimatedTotal', () {
    test('amount per share × shares held', () {
      final total = DividendCalculator.estimatedTotal(
        Decimal.parse('2.50'),
        Decimal.fromInt(100),
      );
      expect(total, Decimal.parse('250'));
    });

    test('zero shares → zero total', () {
      final total = DividendCalculator.estimatedTotal(
        Decimal.parse('2.50'),
        Decimal.zero,
      );
      expect(total, Decimal.zero);
    });
  });

  group('DividendCalculator.calculate — allTimeTotal', () {
    test('sums net amounts of all paid dividends', () {
      final divs = [
        _paid(id: '1', date: DateTime(2022, 3, 1), total: '100'),
        _paid(id: '2', date: DateTime(2023, 3, 1), total: '120'),
      ];
      final s = DividendCalculator.calculate(
        paidDividends: divs,
        currentPrice: Decimal.fromInt(50),
        sharesHeld: Decimal.fromInt(10),
        forYear: 2023,
      );
      expect(s.allTimeTotal, Decimal.fromInt(220));
    });

    test('netAmount subtracts withholding tax', () {
      final divs = [
        _paid(
          id: '1',
          date: DateTime(2023, 3, 1),
          total: '100',
          withholding: '15',
        ),
      ];
      final s = DividendCalculator.calculate(
        paidDividends: divs,
        currentPrice: Decimal.fromInt(50),
        sharesHeld: Decimal.fromInt(10),
        forYear: 2023,
      );
      expect(s.allTimeTotal, Decimal.fromInt(85));
    });
  });

  group('DividendCalculator.calculate — currentYearTotal', () {
    test('only includes dividends from forYear', () {
      final divs = [
        _paid(id: '1', date: DateTime(2022, 3, 1), total: '100'),
        _paid(id: '2', date: DateTime(2023, 3, 1), total: '120'),
        _paid(id: '3', date: DateTime(2023, 9, 1), total: '130'),
      ];
      final s = DividendCalculator.calculate(
        paidDividends: divs,
        currentPrice: Decimal.fromInt(50),
        sharesHeld: Decimal.fromInt(10),
        forYear: 2023,
      );
      expect(s.currentYearTotal, Decimal.fromInt(250));
    });

    test('zero when no dividends in forYear', () {
      final divs = [
        _paid(id: '1', date: DateTime(2021, 6, 1), total: '100'),
      ];
      final s = DividendCalculator.calculate(
        paidDividends: divs,
        currentPrice: Decimal.fromInt(50),
        sharesHeld: Decimal.fromInt(10),
        forYear: 2023,
      );
      expect(s.currentYearTotal, Decimal.zero);
    });
  });

  group('DividendCalculator.calculate — annualYieldPct', () {
    test('returns zero when positionValue is zero', () {
      final divs = [
        _paid(
          id: '1',
          date: DateTime.now().subtract(const Duration(days: 30)),
          total: '100',
        ),
      ];
      final s = DividendCalculator.calculate(
        paidDividends: divs,
        currentPrice: Decimal.zero,
        sharesHeld: Decimal.zero,
      );
      expect(s.annualYieldPct, Decimal.zero);
    });

    test('recent dividends contribute to yield', () {
      // Single dividend within last 12 months: 50 net on 1000 position → 5%
      final divs = [
        _paid(
          id: '1',
          date: DateTime.now().subtract(const Duration(days: 60)),
          total: '50',
        ),
      ];
      final s = DividendCalculator.calculate(
        paidDividends: divs,
        currentPrice: Decimal.fromInt(100),
        sharesHeld: Decimal.fromInt(10), // position = 1000
      );
      expect(s.annualYieldPct, Decimal.fromInt(5));
    });

    test('old dividends (> 12 months) are excluded from yield', () {
      final divs = [
        _paid(
          id: '1',
          date: DateTime.now().subtract(const Duration(days: 400)),
          total: '50',
        ),
      ];
      final s = DividendCalculator.calculate(
        paidDividends: divs,
        currentPrice: Decimal.fromInt(100),
        sharesHeld: Decimal.fromInt(10),
      );
      expect(s.annualYieldPct, Decimal.zero);
    });
  });

  group('DividendCalculator.calculate — manualYieldPct fallback', () {
    test('used as annualYieldPct when no paid dividends', () {
      final s = DividendCalculator.calculate(
        paidDividends: [],
        currentPrice: Decimal.fromInt(100),
        sharesHeld: Decimal.fromInt(10),
        manualYieldPct: Decimal.parse('6.36'),
      );
      expect(s.annualYieldPct, Decimal.parse('6.36'));
    });

    test('used when dividends exist but all are older than 12 months', () {
      final divs = [
        _paid(
          id: '1',
          date: DateTime.now().subtract(const Duration(days: 400)),
          total: '50',
        ),
      ];
      final s = DividendCalculator.calculate(
        paidDividends: divs,
        currentPrice: Decimal.fromInt(100),
        sharesHeld: Decimal.fromInt(10),
        manualYieldPct: Decimal.parse('5'),
      );
      expect(s.annualYieldPct, Decimal.parse('5'));
    });

    test('ignored when recent dividends produce a non-zero yield', () {
      final divs = [
        _paid(
          id: '1',
          date: DateTime.now().subtract(const Duration(days: 30)),
          total: '50',
        ),
      ];
      final s = DividendCalculator.calculate(
        paidDividends: divs,
        currentPrice: Decimal.fromInt(100),
        sharesHeld: Decimal.fromInt(10), // position = 1000, yield = 5%
        manualYieldPct: Decimal.parse('9.99'),
      );
      // computed yield wins; manual override is not used
      expect(s.annualYieldPct, Decimal.fromInt(5));
    });

    test('null manualYieldPct with no dividends → zero yield', () {
      final s = DividendCalculator.calculate(
        paidDividends: [],
        currentPrice: Decimal.fromInt(100),
        sharesHeld: Decimal.fromInt(10),
      );
      expect(s.annualYieldPct, Decimal.zero);
    });

    test('allTimeTotal and currentYearTotal are unaffected by manualYieldPct', () {
      final s = DividendCalculator.calculate(
        paidDividends: [],
        currentPrice: Decimal.fromInt(100),
        sharesHeld: Decimal.fromInt(10),
        manualYieldPct: Decimal.parse('6'),
        forYear: 2024,
      );
      expect(s.allTimeTotal, Decimal.zero);
      expect(s.currentYearTotal, Decimal.zero);
    });
  });

  group('DividendCalculator.convert', () {
    test('scales allTimeTotal and currentYearTotal by exchange rate', () {
      final divs = [
        _paid(id: '1', date: DateTime(2023, 6, 1), total: '200'),
      ];
      final summary = DividendCalculator.calculate(
        paidDividends: divs,
        currentPrice: Decimal.fromInt(50),
        sharesHeld: Decimal.fromInt(10),
        forYear: 2023,
      );
      final rate = ExchangeRate(
        base: 'EUR',
        target: 'USD',
        rate: Decimal.parse('0.9'),
        fetchedAt: DateTime.now(),
        isManualOverride: false,
      );
      final c = DividendCalculator.convert(summary, rate);
      expect(c.allTimeTotal, Decimal.parse('180'));
      expect(c.currentYearTotal, Decimal.parse('180'));
    });

    test('annualYieldPct is not scaled', () {
      final divs = [
        _paid(
          id: '1',
          date: DateTime.now().subtract(const Duration(days: 30)),
          total: '50',
        ),
      ];
      final summary = DividendCalculator.calculate(
        paidDividends: divs,
        currentPrice: Decimal.fromInt(100),
        sharesHeld: Decimal.fromInt(10),
      );
      final rate = ExchangeRate(
        base: 'EUR',
        target: 'USD',
        rate: Decimal.parse('0.9'),
        fetchedAt: DateTime.now(),
        isManualOverride: false,
      );
      final c = DividendCalculator.convert(summary, rate);
      expect(c.annualYieldPct, summary.annualYieldPct);
    });
  });

  group('Dividend.netAmount', () {
    test('totalAmount - withholdingTax', () {
      final d = _paid(id: '1', date: DateTime(2023, 1, 1), total: '100', withholding: '20');
      expect(d.netAmount, Decimal.fromInt(80));
    });

    test('zero withholdingTax → netAmount equals totalAmount', () {
      final d = _paid(id: '1', date: DateTime(2023, 1, 1), total: '100');
      expect(d.netAmount, Decimal.fromInt(100));
    });

    test('null totalAmount → netAmount is zero', () {
      final d = Dividend(
        id: '1',
        stockId: 's1',
        type: DividendType.expected,
        date: DateTime(2024, 6, 1),
        amountPerShare: Decimal.parse('1.5'),
        currency: 'USD',
      );
      expect(d.netAmount, Decimal.zero);
    });
  });
}
