import 'package:decimal/decimal.dart';

class AnalystData {
  const AnalystData({
    required this.targetMeanPrice,
    this.targetLowPrice,
    this.targetHighPrice,
    this.recommendationKey,
    this.numberOfAnalysts,
    this.currency,
  });

  final Decimal targetMeanPrice;
  final Decimal? targetLowPrice;
  final Decimal? targetHighPrice;
  // 'strongBuy' | 'buy' | 'hold' | 'underperform' | 'sell'
  final String? recommendationKey;
  final int? numberOfAnalysts;
  final String? currency;
}
