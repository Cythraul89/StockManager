import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

class PricePoint extends Equatable {
  const PricePoint({
    required this.date,
    required this.price,
    required this.currency,
  });

  final DateTime date;
  final Decimal price;
  // ISO 4217 currency of [price] — Yahoo's trading currency for this symbol.
  final String currency;

  @override
  List<Object?> get props => [date, price, currency];
}
