import 'package:decimal/decimal.dart';

extension DecimalX on Decimal {
  bool get isZero => this == Decimal.zero;
  bool get isPositive => this > Decimal.zero;
  bool get isNegative => this < Decimal.zero;

  // Percentage change from [base] to this.
  Decimal percentChangeFrom(Decimal base) {
    if (base.isZero) return Decimal.zero;
    return ((this - base).toRational() / base.toRational() * Decimal.fromInt(100).toRational())
        .toDecimal(scaleOnInfinitePrecision: 6);
  }

  String toStringFixed(int places) => toStringAsFixed(places);
}

class DecimalMath {
  // Weighted average: sum(value_i * weight_i) / sum(weight_i)
  static Decimal weightedAverage(List<({Decimal value, Decimal weight})> items) {
    if (items.isEmpty) return Decimal.zero;
    final totalWeight = items.fold(Decimal.zero, (acc, e) => acc + e.weight);
    if (totalWeight.isZero) return Decimal.zero;
    final weightedSum =
        items.fold(Decimal.zero, (acc, e) => acc + e.value * e.weight);
    return (weightedSum.toRational() / totalWeight.toRational())
        .toDecimal(scaleOnInfinitePrecision: 10);
  }

  // Clamp to a minimum of zero (used for remaining shares after sells).
  static Decimal clampMin(Decimal value) =>
      value < Decimal.zero ? Decimal.zero : value;
}
