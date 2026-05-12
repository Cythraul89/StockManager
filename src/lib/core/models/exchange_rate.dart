import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

class ExchangeRate extends Equatable {
  const ExchangeRate({
    required this.base,
    required this.target,
    required this.rate,
    required this.fetchedAt,
    required this.isManualOverride,
  });

  final String base;
  final String target;
  final Decimal rate;
  final DateTime fetchedAt;
  final bool isManualOverride;

  static const cacheTtl = Duration(hours: 1);

  bool get isStale =>
      !isManualOverride &&
      DateTime.now().difference(fetchedAt) > cacheTtl;

  Decimal convert(Decimal amount) => amount * rate;

  @override
  List<Object?> get props =>
      [base, target, rate, fetchedAt, isManualOverride];
}
