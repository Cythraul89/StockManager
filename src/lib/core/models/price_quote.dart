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
  });

  final String stockId;
  final Decimal price;
  final String currency;
  final DateTime fetchedAt;
  final bool isStale;
  final bool isManualOverride;

  static const cacheTtl = Duration(hours: 1);

  PriceQuote withStaleness() => PriceQuote(
        stockId: stockId,
        price: price,
        currency: currency,
        fetchedAt: fetchedAt,
        // Manual prices are never stale — the user controls them.
        isStale: isManualOverride
            ? false
            : DateTime.now().difference(fetchedAt) > cacheTtl,
        isManualOverride: isManualOverride,
      );

  @override
  List<Object?> get props =>
      [stockId, price, currency, fetchedAt, isStale, isManualOverride];
}
