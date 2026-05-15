import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

class AnalystData extends Equatable {
  const AnalystData({
    required this.targetMeanPrice,
    this.targetLowPrice,
    this.targetHighPrice,
    this.recommendationKey,
    this.numberOfAnalysts,
    this.currency,
    this.strongBuyCount,
    this.buyCount,
    this.holdCount,
    this.sellCount,
    this.strongSellCount,
    this.fiftyTwoWeekLow,
    this.fiftyTwoWeekHigh,
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
  // Yahoo's financial-reporting currency — kept for diagnostics only.
  // Analyst price targets are always in the trading currency (quoteCurrency);
  // do not use this field for price conversion.
  final String? currency;

  // Recommendation consensus breakdown (recommendationTrend, most recent period)
  final int? strongBuyCount;
  final int? buyCount;
  final int? holdCount;
  final int? sellCount;
  final int? strongSellCount;

  // 52-week price range (summaryDetail)
  final Decimal? fiftyTwoWeekLow;
  final Decimal? fiftyTwoWeekHigh;

  // Valuation (summaryDetail + defaultKeyStatistics)
  final Decimal? trailingPE;
  final Decimal? forwardPE;
  final Decimal? trailingEps;

  AnalystData copyWith({
    Decimal? targetMeanPrice,
    Decimal? targetLowPrice,
    Decimal? targetHighPrice,
    String? recommendationKey,
    int? numberOfAnalysts,
    String? currency,
    int? strongBuyCount,
    int? buyCount,
    int? holdCount,
    int? sellCount,
    int? strongSellCount,
    Decimal? fiftyTwoWeekLow,
    Decimal? fiftyTwoWeekHigh,
    Decimal? trailingPE,
    Decimal? forwardPE,
    Decimal? trailingEps,
  }) {
    return AnalystData(
      targetMeanPrice: targetMeanPrice ?? this.targetMeanPrice,
      targetLowPrice: targetLowPrice ?? this.targetLowPrice,
      targetHighPrice: targetHighPrice ?? this.targetHighPrice,
      recommendationKey: recommendationKey ?? this.recommendationKey,
      numberOfAnalysts: numberOfAnalysts ?? this.numberOfAnalysts,
      currency: currency ?? this.currency,
      strongBuyCount: strongBuyCount ?? this.strongBuyCount,
      buyCount: buyCount ?? this.buyCount,
      holdCount: holdCount ?? this.holdCount,
      sellCount: sellCount ?? this.sellCount,
      strongSellCount: strongSellCount ?? this.strongSellCount,
      fiftyTwoWeekLow: fiftyTwoWeekLow ?? this.fiftyTwoWeekLow,
      fiftyTwoWeekHigh: fiftyTwoWeekHigh ?? this.fiftyTwoWeekHigh,
      trailingPE: trailingPE ?? this.trailingPE,
      forwardPE: forwardPE ?? this.forwardPE,
      trailingEps: trailingEps ?? this.trailingEps,
    );
  }

  @override
  List<Object?> get props => [
        targetMeanPrice,
        targetLowPrice,
        targetHighPrice,
        recommendationKey,
        numberOfAnalysts,
        currency,
        strongBuyCount,
        buyCount,
        holdCount,
        sellCount,
        strongSellCount,
        fiftyTwoWeekLow,
        fiftyTwoWeekHigh,
        trailingPE,
        forwardPE,
        trailingEps,
      ];
}
