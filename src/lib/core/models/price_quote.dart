import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

class PriceQuote extends Equatable {
  const PriceQuote({
    required this.stockId,
    required this.price,
    required this.currency,
    required this.fetchedAt,
    this.isStale = false,
    this.isManualOverride = false,
    this.dayChangePct,
  });

  final String stockId;
  final Decimal price;
  final String currency;
  final DateTime fetchedAt;
  final bool isStale;
  final bool isManualOverride;
  // Percentage change from the previous close, as returned by Yahoo Finance.
  // Null for manual overrides and DB-cached quotes (not persisted).
  final Decimal? dayChangePct;

  static const cacheTtl = Duration(hours: 1);

  PriceQuote withStaleness() => PriceQuote(
        stockId: stockId,
        price: price,
        currency: currency,
        fetchedAt: fetchedAt,
        isStale: isManualOverride
            ? false
            : DateTime.now().difference(fetchedAt) > cacheTtl,
        isManualOverride: isManualOverride,
        dayChangePct: dayChangePct,
      );

  @override
  List<Object?> get props =>
      [stockId, price, currency, fetchedAt, isStale, isManualOverride, dayChangePct];
}
