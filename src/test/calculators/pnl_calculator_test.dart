import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_manager/core/calculators/pnl_calculator.dart';
import 'package:stock_manager/core/models/exchange_rate.dart';
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

void main() {
  final t0 = DateTime(2023, 1, 1);
  final t1 = DateTime(2023, 6, 1);

  group('PnlCalculator.calculate', () {
    test('unrealised P&L = currentValue - costBasis', () {
      final r = PnlCalculator.calculate(
        transactions: [_buy(id: '1', at: t0, shares: '10', price: '100')],
        splits: [],
        currentPrice: Decimal.fromInt(150),
      );
      expect(r.currentValue, Decimal.fromInt(1500));
      expect(r.totalInvested, Decimal.fromInt(1000));
      expect(r.unrealisedPnl, Decimal.fromInt(500));
      expect(r.realisedPnl, Decimal.zero);
    });

    test('unrealised P&L percentage is 50% for a 100→150 move', () {
      final r = PnlCalculator.calculate(
        transactions: [_buy(id: '1', at: t0, shares: '10', price: '100')],
        splits: [],
        currentPrice: Decimal.fromInt(150),
      );
      expect(r.unrealisedPnlPct, Decimal.fromInt(50));
    });

    test('negative unrealised P&L when price falls', () {
      final r = PnlCalculator.calculate(
        transactions: [_buy(id: '1', at: t0, shares: '10', price: '100')],
        splits: [],
        currentPrice: Decimal.fromInt(80),
      );
      expect(r.unrealisedPnl, Decimal.fromInt(-200));
    });

    test('realised P&L from full sell at profit', () {
      // Buy 10 @ 100 (cost 1000), sell 10 @ 150 (proceeds 1500) → +500
      final r = PnlCalculator.calculate(
        transactions: [
          _buy(id: '1', at: t0, shares: '10', price: '100'),
          _sell(id: '2', at: t1, shares: '10', price: '150'),
        ],
        splits: [],
        currentPrice: Decimal.fromInt(150),
      );
      expect(r.realisedPnl, Decimal.fromInt(500));
      expect(r.currentValue, Decimal.zero); // 0 shares remain
    });

    test('sell fees reduce realised P&L', () {
      // Buy 10 @ 100, sell 10 @ 150 with fee 10 → proceeds 1490 → realised 490
      final r = PnlCalculator.calculate(
        transactions: [
          _buy(id: '1', at: t0, shares: '10', price: '100'),
          _sell(id: '2', at: t1, shares: '10', price: '150', fees: '10'),
        ],
        splits: [],
        currentPrice: Decimal.fromInt(150),
      );
      expect(r.realisedPnl, Decimal.fromInt(490));
    });

    test('buy fees increase cost basis and reduce realised P&L', () {
      // Buy 10 @ 100 + fee 10 → cost 1010; sell 10 @ 150 → realised 490
      final r = PnlCalculator.calculate(
        transactions: [
          _buy(id: '1', at: t0, shares: '10', price: '100', fees: '10'),
          _sell(id: '2', at: t1, shares: '10', price: '150'),
        ],
        splits: [],
        currentPrice: Decimal.fromInt(150),
      );
      expect(r.realisedPnl, Decimal.fromInt(490));
    });

    test('sell beyond current holding is clamped — no negative shares', () {
      // Data error: sell more shares than held; realised should not go negative
      final r = PnlCalculator.calculate(
        transactions: [
          _buy(id: '1', at: t0, shares: '5', price: '100'),
          _sell(id: '2', at: t1, shares: '10', price: '150'),
        ],
        splits: [],
        currentPrice: Decimal.fromInt(150),
      );
      expect(r.currentValue >= Decimal.zero, isTrue);
    });
  });

  group('PnlCalculator.convert', () {
    test('scales monetary fields by exchange rate', () {
      final base = PnlCalculator.calculate(
        transactions: [_buy(id: '1', at: t0, shares: '10', price: '100')],
        splits: [],
        currentPrice: Decimal.fromInt(150),
      );
      // USD → EUR @ 0.9: ExchangeRate(base: 'EUR', target: 'USD', rate: 0.9)
      final rate = ExchangeRate(
        base: 'EUR',
        target: 'USD',
        rate: Decimal.parse('0.9'),
        fetchedAt: DateTime.now(),
        isManualOverride: false,
      );
      final c = PnlCalculator.convert(base, rate);
      expect(c.currentValue, Decimal.parse('1350'));
      expect(c.totalInvested, Decimal.parse('900'));
      expect(c.unrealisedPnl, Decimal.parse('450'));
    });

    test('unrealisedPnlPct is not scaled (it is unit-less)', () {
      final base = PnlCalculator.calculate(
        transactions: [_buy(id: '1', at: t0, shares: '10', price: '100')],
        splits: [],
        currentPrice: Decimal.fromInt(150),
      );
      final rate = ExchangeRate(
        base: 'EUR',
        target: 'USD',
        rate: Decimal.parse('0.9'),
        fetchedAt: DateTime.now(),
        isManualOverride: false,
      );
      final c = PnlCalculator.convert(base, rate);
      expect(c.unrealisedPnlPct, base.unrealisedPnlPct);
    });
  });
}
