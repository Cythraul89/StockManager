import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_manager/core/calculators/portfolio_calculator.dart';
import 'package:stock_manager/core/models/stock_split.dart';
import 'package:stock_manager/core/models/transaction.dart';

StockTransaction _buy({
  required String id,
  required DateTime at,
  required String shares,
  required String price,
  String fees = '0',
}) =>
    StockTransaction(
      id: id,
      stockId: 's1',
      type: TransactionType.buy,
      executedAt: at,
      shares: Decimal.parse(shares),
      pricePerShare: Decimal.parse(price),
      currency: 'USD',
      fees: Decimal.parse(fees),
    );

StockTransaction _sell({
  required String id,
  required DateTime at,
  required String shares,
  required String price,
  String fees = '0',
}) =>
    StockTransaction(
      id: id,
      stockId: 's1',
      type: TransactionType.sell,
      executedAt: at,
      shares: Decimal.parse(shares),
      pricePerShare: Decimal.parse(price),
      currency: 'USD',
      fees: Decimal.parse(fees),
    );

StockSplit _split({
  required DateTime at,
  required int from,
  required int to,
}) =>
    StockSplit(
      id: 'sp1',
      stockId: 's1',
      date: at,
      fromShares: from,
      toShares: to,
    );

void main() {
  final t0 = DateTime(2023, 1, 1);
  final t1 = DateTime(2023, 6, 1);
  final t2 = DateTime(2024, 1, 1);

  group('PortfolioCalculator.calculate', () {
    test('single buy — shares, avgBuyPrice, totalInvested', () {
      final r = PortfolioCalculator.calculate(
        [_buy(id: '1', at: t0, shares: '10', price: '100')],
        [],
      );
      expect(r.sharesHeld, Decimal.fromInt(10));
      expect(r.avgBuyPrice, Decimal.fromInt(100));
      expect(r.totalInvested, Decimal.fromInt(1000));
    });

    test('fees are included in cost basis', () {
      final r = PortfolioCalculator.calculate(
        [_buy(id: '1', at: t0, shares: '10', price: '100', fees: '5')],
        [],
      );
      expect(r.totalInvested, Decimal.fromInt(1005));
      expect(r.avgBuyPrice, Decimal.parse('100.5'));
    });

    test('weighted average across two buys', () {
      final r = PortfolioCalculator.calculate(
        [
          _buy(id: '1', at: t0, shares: '10', price: '100'),
          _buy(id: '2', at: t1, shares: '10', price: '200'),
        ],
        [],
      );
      expect(r.sharesHeld, Decimal.fromInt(20));
      expect(r.totalInvested, Decimal.fromInt(3000));
      expect(r.avgBuyPrice, Decimal.fromInt(150));
    });

    test('partial sell reduces shares and cost basis proportionally', () {
      final r = PortfolioCalculator.calculate(
        [
          _buy(id: '1', at: t0, shares: '10', price: '100'),
          _sell(id: '2', at: t1, shares: '5', price: '120'),
        ],
        [],
      );
      expect(r.sharesHeld, Decimal.fromInt(5));
      expect(r.totalInvested, Decimal.fromInt(500));
    });

    test('full sell results in zero position', () {
      final r = PortfolioCalculator.calculate(
        [
          _buy(id: '1', at: t0, shares: '10', price: '100'),
          _sell(id: '2', at: t1, shares: '10', price: '150'),
        ],
        [],
      );
      expect(r.sharesHeld, Decimal.zero);
      expect(r.totalInvested, Decimal.zero);
      expect(r.avgBuyPrice, Decimal.zero);
    });

    test('4:1 forward split adjusts historical shares and price', () {
      // Buy 10 @ 100; after 4:1 split → 40 shares @ 25, cost basis unchanged
      final r = PortfolioCalculator.calculate(
        [_buy(id: '1', at: t0, shares: '10', price: '100')],
        [_split(at: t1, from: 1, to: 4)],
      );
      expect(r.sharesHeld, Decimal.fromInt(40));
      expect(r.avgBuyPrice, Decimal.parse('25'));
      expect(r.totalInvested, Decimal.fromInt(1000));
    });

    test('1:2 reverse split adjusts historical shares and price', () {
      // Buy 10 @ 100; after 1:2 reverse split → 5 shares @ 200
      final r = PortfolioCalculator.calculate(
        [_buy(id: '1', at: t0, shares: '10', price: '100')],
        [_split(at: t1, from: 2, to: 1)],
      );
      expect(r.sharesHeld, Decimal.fromInt(5));
      expect(r.avgBuyPrice, Decimal.parse('200'));
      expect(r.totalInvested, Decimal.fromInt(1000));
    });

    test('split only applies to transactions before split date', () {
      // Buy 10 @ t0 (pre-split); 4:1 split @ t1; buy 5 @ t2 (post-split).
      // Pre-split buy → 40 adjusted + post-split buy → 5 = 45 total.
      final r = PortfolioCalculator.calculate(
        [
          _buy(id: '1', at: t0, shares: '10', price: '100'),
          _buy(id: '2', at: t2, shares: '5', price: '50'),
        ],
        [_split(at: t1, from: 1, to: 4)],
      );
      expect(r.sharesHeld, Decimal.fromInt(45));
    });
  });

  group('PortfolioCalculator.splitMultiplierAfter', () {
    test('returns 1 with no splits', () {
      expect(PortfolioCalculator.splitMultiplierAfter(t0, []), Decimal.one);
    });

    test('applies splits strictly after txDate', () {
      final splits = [_split(at: t1, from: 1, to: 4)];
      expect(
        PortfolioCalculator.splitMultiplierAfter(t0, splits),
        Decimal.fromInt(4),
      );
    });

    test('ignores splits on or before txDate', () {
      final splits = [_split(at: t0, from: 1, to: 4)];
      expect(
        PortfolioCalculator.splitMultiplierAfter(t0, splits),
        Decimal.one,
      );
    });

    test('chains multiple splits multiplicatively', () {
      final splits = [
        _split(at: t1, from: 1, to: 2),
        _split(at: t2, from: 1, to: 3),
      ];
      expect(
        PortfolioCalculator.splitMultiplierAfter(t0, splits),
        Decimal.fromInt(6),
      );
    });
  });

  group('PortfolioCalculator.sharesAtDate', () {
    test('counts shares bought on or before asOf', () {
      final shares = PortfolioCalculator.sharesAtDate(
        [_buy(id: '1', at: t0, shares: '10', price: '100')],
        [],
        t0,
      );
      expect(shares, Decimal.fromInt(10));
    });

    test('excludes transactions strictly after asOf', () {
      final shares = PortfolioCalculator.sharesAtDate(
        [
          _buy(id: '1', at: t0, shares: '10', price: '100'),
          _buy(id: '2', at: t2, shares: '5', price: '50'),
        ],
        [],
        t1,
      );
      expect(shares, Decimal.fromInt(10));
    });

    test('applies splits between txDate and asOf', () {
      // Buy 10 @ t0, 4:1 split @ t1, check at t2 → 40 shares
      final shares = PortfolioCalculator.sharesAtDate(
        [_buy(id: '1', at: t0, shares: '10', price: '100')],
        [_split(at: t1, from: 1, to: 4)],
        t2,
      );
      expect(shares, Decimal.fromInt(40));
    });

    test('does not apply splits after asOf', () {
      // Buy 10 @ t0, split @ t2, check at t1 (before split) → still 10
      final shares = PortfolioCalculator.sharesAtDate(
        [_buy(id: '1', at: t0, shares: '10', price: '100')],
        [_split(at: t2, from: 1, to: 4)],
        t1,
      );
      expect(shares, Decimal.fromInt(10));
    });
  });
}
