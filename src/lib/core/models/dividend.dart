import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

enum DividendType { paid, expected }

class Dividend extends Equatable {
  const Dividend({
    required this.id,
    required this.stockId,
    required this.type,
    required this.date,
    required this.amountPerShare,
    this.totalAmount,
    required this.currency,
    this.withholdingTax,
    this.notes,
  });

  final String id;
  final String stockId;
  final DividendType type;
  final DateTime date;
  final Decimal amountPerShare;
  // null for expected dividends; computed from current holdings on display
  final Decimal? totalAmount;
  final String currency;
  final Decimal? withholdingTax;
  final String? notes;

  Decimal get netAmount =>
      (totalAmount ?? Decimal.zero) - (withholdingTax ?? Decimal.zero);

  Dividend copyWith({
    String? id,
    String? stockId,
    DividendType? type,
    DateTime? date,
    Decimal? amountPerShare,
    Decimal? totalAmount,
    String? currency,
    Decimal? withholdingTax,
    String? notes,
  }) =>
      Dividend(
        id: id ?? this.id,
        stockId: stockId ?? this.stockId,
        type: type ?? this.type,
        date: date ?? this.date,
        amountPerShare: amountPerShare ?? this.amountPerShare,
        totalAmount: totalAmount ?? this.totalAmount,
        currency: currency ?? this.currency,
        withholdingTax: withholdingTax ?? this.withholdingTax,
        notes: notes ?? this.notes,
      );

  @override
  List<Object?> get props => [
        id,
        stockId,
        type,
        date,
        amountPerShare,
        totalAmount,
        currency,
        withholdingTax,
        notes,
      ];
}
