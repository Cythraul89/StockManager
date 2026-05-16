import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

class PricePoint extends Equatable {
  const PricePoint({required this.date, required this.price});

  final DateTime date;
  final Decimal price;

  @override
  List<Object?> get props => [date, price];
}
