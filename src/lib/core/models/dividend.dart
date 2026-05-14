import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

enum DividendType { paid, expected }

enum DividendSource { manual, auto }

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
    this.source = DividendSource.manual,
    this.confirmed = true,
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
  final DividendSource source;
  // Always true for manual entries; false = awaiting user confirmation for auto-fetched paid dividends
  final bool confirmed;

  bool get isPendingConfirmation =>
      source == DividendSource.auto &&
      type == DividendType.paid &&
      !confirmed;

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
    DividendSource? source,
    bool? confirmed,
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
        source: source ?? this.source,
        confirmed: confirmed ?? this.confirmed,
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
        source,
        confirmed,
      ];
}
