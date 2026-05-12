import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

class StockSplit extends Equatable {
  const StockSplit({
    required this.id,
    required this.stockId,
    required this.date,
    required this.fromShares,
    required this.toShares,
  });

  final String id;
  final String stockId;
  final DateTime date;
  final int fromShares;
  final int toShares;

  // e.g. 4:1 split → ratio = 4
  Decimal get ratio =>
      Decimal.fromInt(toShares) / Decimal.fromInt(fromShares).toRational();

  @override
  List<Object?> get props => [id, stockId, date, fromShares, toShares];
}
