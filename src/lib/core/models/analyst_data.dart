import 'package:decimal/decimal.dart';

class AnalystData {
  const AnalystData({
    required this.targetMeanPrice,
    this.targetLowPrice,
    this.targetHighPrice,
    this.recommendationKey,
    this.numberOfAnalysts,
    this.currency,
    // Recommendation consensus breakdown (recommendationTrend, most recent period)
    this.strongBuyCount,
    this.buyCount,
    this.holdCount,
    this.sellCount,
    this.strongSellCount,
    // 52-week range (summaryDetail)
    this.fiftyTwoWeekLow,
    this.fiftyTwoWeekHigh,
    // Valuation (summaryDetail + defaultKeyStatistics)
    this.trailingPE,
    this.forwardPE,
    this.trailingEps,
  });

  // Price targets (financialData)
  final Decimal targetMeanPrice;
  final Decimal? targetLowPrice;
  final Decimal? targetHighPrice;
  final String? recommendationKey;
  final int? numberOfAnalysts;
  final String? currency;

  // Consensus breakdown
  final int? strongBuyCount;
  final int? buyCount;
  final int? holdCount;
  final int? sellCount;
  final int? strongSellCount;

  // 52-week price range
  final Decimal? fiftyTwoWeekLow;
  final Decimal? fiftyTwoWeekHigh;

  // Valuation
  final Decimal? trailingPE;
  final Decimal? forwardPE;
  final Decimal? trailingEps;
}
