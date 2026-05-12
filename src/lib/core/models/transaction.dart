import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

enum TransactionType { buy, sell }

class StockTransaction extends Equatable {
  const StockTransaction({
    required this.id,
    required this.stockId,
    required this.type,
    required this.executedAt,
    required this.shares,
    required this.pricePerShare,
    required this.currency,
    required this.fees,
    this.notes,
  });

  final String id;
  final String stockId;
  final TransactionType type;
  final DateTime executedAt;
  final Decimal shares;
  final Decimal pricePerShare;
  final String currency;
  final Decimal fees;
  final String? notes;

  Decimal get totalCost => shares * pricePerShare + fees;

  StockTransaction copyWith({
    String? id,
    String? stockId,
    TransactionType? type,
    DateTime? executedAt,
    Decimal? shares,
    Decimal? pricePerShare,
    String? currency,
    Decimal? fees,
    String? notes,
  }) =>
      StockTransaction(
        id: id ?? this.id,
        stockId: stockId ?? this.stockId,
        type: type ?? this.type,
        executedAt: executedAt ?? this.executedAt,
        shares: shares ?? this.shares,
        pricePerShare: pricePerShare ?? this.pricePerShare,
        currency: currency ?? this.currency,
        fees: fees ?? this.fees,
        notes: notes ?? this.notes,
      );

  @override
  List<Object?> get props =>
      [id, stockId, type, executedAt, shares, pricePerShare, currency, fees, notes];
}
