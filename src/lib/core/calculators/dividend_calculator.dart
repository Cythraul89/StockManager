import 'package:decimal/decimal.dart';

import '../models/dividend.dart';
import '../models/exchange_rate.dart';

class DividendSummary {
  const DividendSummary({
    required this.allTimeTotal,
    required this.currentYearTotal,
    required this.annualYieldPct,
  });

  final Decimal allTimeTotal;
  final Decimal currentYearTotal;
  final Decimal annualYieldPct;
}

class DividendCalculator {
  static DividendSummary calculate({
    required List<Dividend> paidDividends,
    required Decimal currentPrice,
    required Decimal sharesHeld,
    int? forYear,
    Decimal? manualYieldPct,
  }) {
    final year = forYear ?? DateTime.now().year;

    Decimal allTime = Decimal.zero;
    Decimal currentYear = Decimal.zero;

    for (final d in paidDividends) {
      final net = d.netAmount;
      allTime = allTime + net;
      if (d.date.year == year) currentYear = currentYear + net;
    }

    final annualYield = _annualYield(paidDividends, currentPrice, sharesHeld);
    // When no paid dividends produce a yield (e.g. fixed-income assets that pay
    // interest instead of dividends), fall back to the manual override.
    final effectiveYield = (annualYield == Decimal.zero && manualYieldPct != null)
        ? manualYieldPct
        : annualYield;

    return DividendSummary(
      allTimeTotal: allTime,
      currentYearTotal: currentYear,
      annualYieldPct: effectiveYield,
    );
  }

  // Annual dividend yield = (total paid last 12 months / (shares * current price)) * 100
  static Decimal _annualYield(
    List<Dividend> paid,
    Decimal currentPrice,
    Decimal sharesHeld,
  ) {
    final cutoff = DateTime.now().subtract(const Duration(days: 365));
    Decimal annual = Decimal.zero;
    for (final d in paid) {
      if (d.date.isAfter(cutoff)) annual = annual + d.netAmount;
    }
    final positionValue = sharesHeld * currentPrice;
    if (positionValue == Decimal.zero) return Decimal.zero;
    return (annual.toRational() / positionValue.toRational() * Decimal.fromInt(100).toRational())
        .toDecimal(scaleOnInfinitePrecision: 4);
  }

  // Estimate total for an expected dividend given current share count.
  static Decimal estimatedTotal(Decimal amountPerShare, Decimal sharesHeld) =>
      amountPerShare * sharesHeld;

  // Convert a DividendSummary to preferred currency.
  static DividendSummary convert(DividendSummary summary, ExchangeRate rate) =>
      DividendSummary(
        allTimeTotal: rate.convert(summary.allTimeTotal),
        currentYearTotal: rate.convert(summary.currentYearTotal),
        annualYieldPct: summary.annualYieldPct, // yield % is unitless
      );
}
