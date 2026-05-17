import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/dashboard_provider.dart';
import '../stocks/stocks_provider.dart';

class DividendEstimate {
  const DividendEstimate({
    required this.total,
    required this.coveredStocks,
    required this.totalStocks,
    required this.currency,
  });

  final Decimal total;
  // Number of held stocks for which analyst yield data was available.
  final int coveredStocks;
  // Total number of held stocks (with a price).
  final int totalStocks;
  final String currency;
}

/// Estimated annual dividend income for the whole portfolio (preferred currency).
///
/// For each held stock with a price, multiplies currentValue by Yahoo's
/// 5-year average dividend yield from [analystDataProvider]. Only stocks
/// for which analyst data is already cached are included — no extra API calls
/// are triggered. Returns null when no held stock has yield data.
final estimatedAnnualDividendProvider = Provider<DividendEstimate?>((ref) {
  final summary = ref.watch(portfolioSummaryProvider).valueOrNull;
  if (summary == null) return null;

  final heldItems = summary.stockItems
      .where((item) => item.sharesHeld.isPositive && item.hasPrice)
      .toList();
  if (heldItems.isEmpty) return null;

  var total = Decimal.zero;
  var covered = 0;

  for (final item in heldItems) {
    final yield_ = ref
        .watch(analystDataProvider(item.stock.id))
        .valueOrNull
        ?.fiveYearAvgDividendYield;
    if (yield_ == null || !yield_.isPositive) continue;
    total += (item.currentValue.toRational() *
            yield_.toRational() /
            Decimal.fromInt(100).toRational())
        .toDecimal(scaleOnInfinitePrecision: 2);
    covered++;
  }

  return DividendEstimate(
    total: total,
    coveredStocks: covered,
    totalStocks: heldItems.length,
    currency: summary.currency,
  );
});
