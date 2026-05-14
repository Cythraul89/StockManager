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

  // Finds the rate that converts [from] → [to]. Returns null when from == to
  // or no matching rate exists.
  // Convention: stored as ExchangeRate(base: to, target: from, rate: toPerFrom),
  // so convert(amount_in_from) = amount * rate = amount_in_to.
  static ExchangeRate? find(
      List<ExchangeRate> rates, String from, String to) {
    if (from == to) return null;
    for (final r in rates) {
      if (r.base == to && r.target == from) return r;
    }
    return null;
  }

  bool get isStale =>
      !isManualOverride &&
      DateTime.now().difference(fetchedAt) > cacheTtl;

  Decimal convert(Decimal amount) => amount * rate;

  @override
  List<Object?> get props =>
      [base, target, rate, fetchedAt, isManualOverride];
}
