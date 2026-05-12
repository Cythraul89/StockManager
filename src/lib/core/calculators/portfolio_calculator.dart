import 'package:decimal/decimal.dart';

import '../models/stock_split.dart';
import '../models/transaction.dart';
import '../utils/decimal_math.dart';

class PositionSummary {
  const PositionSummary({
    required this.sharesHeld,
    required this.avgBuyPrice,
    required this.totalInvested,
  });

  final Decimal sharesHeld;
  final Decimal avgBuyPrice;
  // Cost basis of currently held shares in the transaction currency.
  final Decimal totalInvested;

  static const zero = PositionSummary(
    sharesHeld: Decimal.zero,
    avgBuyPrice: Decimal.zero,
    totalInvested: Decimal.zero,
  );
}

class PortfolioCalculator {
  // Computes the current position for a stock given its transactions and splits.
  // Splits adjust historical share counts and prices so raw rows are never mutated.
  static PositionSummary calculate(
    List<StockTransaction> transactions,
    List<StockSplit> splits,
  ) {
    // Sort ascending so we apply splits in chronological order.
    final sortedTx = List.of(transactions)
      ..sort((a, b) => a.executedAt.compareTo(b.executedAt));
    final sortedSplits = List.of(splits)
      ..sort((a, b) => a.date.compareTo(b.date));

    Decimal sharesHeld = Decimal.zero;
    Decimal totalCostBasis = Decimal.zero;

    for (final tx in sortedTx) {
      // Split multiplier: product of all split ratios that occurred AFTER tx.
      final multiplier = _splitMultiplierAfter(tx.executedAt, sortedSplits);
      final adjustedShares = tx.shares * multiplier;
      final adjustedPrice =
          (tx.pricePerShare.toRational() / multiplier.toRational())
              .toDecimal(scaleOnInfinitePrecision: 10);

      if (tx.type == TransactionType.buy) {
        sharesHeld = sharesHeld + adjustedShares;
        totalCostBasis = totalCostBasis + adjustedShares * adjustedPrice + tx.fees;
      } else {
        // Sell: reduce held shares and cost basis proportionally (FIFO not needed;
        // average-cost method is standard for retail investors in most jurisdictions).
        if (sharesHeld.isZero) continue;
        final sellRatio =
            (adjustedShares.toRational() / sharesHeld.toRational())
                .toDecimal(scaleOnInfinitePrecision: 10);
        final costReduction = totalCostBasis * sellRatio;
        sharesHeld = DecimalMath.clampMin(sharesHeld - adjustedShares);
        totalCostBasis = DecimalMath.clampMin(totalCostBasis - costReduction);
      }
    }

    final avgBuyPrice = sharesHeld.isZero
        ? Decimal.zero
        : (totalCostBasis.toRational() / sharesHeld.toRational())
            .toDecimal(scaleOnInfinitePrecision: 10);

    return PositionSummary(
      sharesHeld: sharesHeld,
      avgBuyPrice: avgBuyPrice,
      totalInvested: totalCostBasis,
    );
  }

  static Decimal _splitMultiplierAfter(
      DateTime txDate, List<StockSplit> splits) {
    var multiplier = Decimal.one;
    for (final split in splits) {
      if (split.date.isAfter(txDate)) {
        multiplier = multiplier * split.ratio;
      }
    }
    return multiplier;
  }
}
