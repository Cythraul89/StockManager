import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

class PriceQuote extends Equatable {
  const PriceQuote({
    required this.stockId,
    required this.price,
    required this.currency,
    required this.fetchedAt,
    this.isStale = false,
  });

  final String stockId;
  final Decimal price;
  final String currency;
  final DateTime fetchedAt;
  // true when fetched_at is older than the cache TTL (1 hour)
  final bool isStale;

  static const cacheTtl = Duration(hours: 1);

  PriceQuote withStaleness() => PriceQuote(
        stockId: stockId,
        price: price,
        currency: currency,
        fetchedAt: fetchedAt,
        isStale: DateTime.now().difference(fetchedAt) > cacheTtl,
      );

  @override
  List<Object?> get props => [stockId, price, currency, fetchedAt, isStale];
}
