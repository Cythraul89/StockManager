import 'package:decimal/decimal.dart';

import '../models/exchange_rate.dart';
import '../models/stock_split.dart';
import '../models/transaction.dart';
import '../utils/decimal_math.dart';
import 'portfolio_calculator.dart';

class PnlResult {
  const PnlResult({
    required this.unrealisedPnl,
    required this.unrealisedPnlPct,
    required this.realisedPnl,
    required this.currentValue,
    required this.totalInvested,
  });

  final Decimal unrealisedPnl;
  final Decimal unrealisedPnlPct;
  final Decimal realisedPnl;
  final Decimal currentValue;
  final Decimal totalInvested;
}

class PnlCalculator {
  // Computes P&L for a single stock position.
  // [currentPrice] is in the stock's native currency.
  // Returns values in the stock's native currency.
  static PnlResult calculate({
    required List<StockTransaction> transactions,
    required List<StockSplit> splits,
    required Decimal currentPrice,
  }) {
    final position = PortfolioCalculator.calculate(transactions, splits);
    final currentValue = position.sharesHeld * currentPrice;

    final unrealisedPnl = currentValue - position.totalInvested;
    final unrealisedPnlPct =
        currentValue.percentChangeFrom(position.totalInvested);

    final realisedPnl = _realisedPnl(transactions, splits);

    return PnlResult(
      unrealisedPnl: unrealisedPnl,
      unrealisedPnlPct: unrealisedPnlPct,
      realisedPnl: realisedPnl,
      currentValue: currentValue,
      totalInvested: position.totalInvested,
    );
  }

  // Converts a PnlResult to the preferred display currency.
  static PnlResult convert(PnlResult result, ExchangeRate rate) => PnlResult(
        unrealisedPnl: rate.convert(result.unrealisedPnl),
        unrealisedPnlPct: result.unrealisedPnlPct,
        realisedPnl: rate.convert(result.realisedPnl),
        currentValue: rate.convert(result.currentValue),
        totalInvested: rate.convert(result.totalInvested),
      );

  static Decimal _realisedPnl(
      List<StockTransaction> transactions, List<StockSplit> splits) {
    final sortedTx = List.of(transactions)
      ..sort((a, b) => a.executedAt.compareTo(b.executedAt));
    final sortedSplits = List.of(splits)
      ..sort((a, b) => a.date.compareTo(b.date));

    Decimal runningCostBasis = Decimal.zero;
    Decimal runningShares = Decimal.zero;
    Decimal realisedPnl = Decimal.zero;

    for (final tx in sortedTx) {
      final multiplier = PortfolioCalculator.splitMultiplierAfter(
          tx.executedAt, sortedSplits);
      final adjustedShares = tx.shares * multiplier;
      final adjustedPrice =
          (tx.pricePerShare.toRational() / multiplier.toRational())
              .toDecimal(scaleOnInfinitePrecision: 10);

      if (tx.type == TransactionType.buy) {
        runningShares = runningShares + adjustedShares;
        runningCostBasis =
            runningCostBasis + adjustedShares * adjustedPrice + tx.fees;
      } else {
        if (runningShares.isZero) continue;
        // Clamp to owned shares — sells beyond current holding are data errors.
        final actualSold = adjustedShares > runningShares
            ? runningShares
            : adjustedShares;
        final avgCost =
            (runningCostBasis.toRational() / runningShares.toRational())
                .toDecimal(scaleOnInfinitePrecision: 10);
        final proceeds = actualSold * adjustedPrice - tx.fees;
        realisedPnl = realisedPnl + proceeds - actualSold * avgCost;
        runningShares = DecimalMath.clampMin(runningShares - actualSold);
        runningCostBasis =
            runningShares.isZero ? Decimal.zero : runningShares * avgCost;
      }
    }
    return realisedPnl;
  }
}
