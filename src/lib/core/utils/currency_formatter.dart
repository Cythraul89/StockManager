import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

class CurrencyFormatter {
  // Returns a locale-aware formatted string, e.g. "€1,234.56" or "USD 1,234.56".
  static String format(
    Decimal amount,
    String currencyCode, {
    String locale = 'en_US',
    int decimalDigits = 2,
  }) {
    final formatter = NumberFormat.currency(
      locale: locale,
      symbol: _symbol(currencyCode),
      decimalDigits: decimalDigits,
    );
    return formatter.format(amount.toDouble());
  }

  // Compact format for list tiles: "1.23k", "4.56M" etc.
  static String compact(Decimal amount, String currencyCode) {
    final formatter = NumberFormat.compactCurrency(
      symbol: _symbol(currencyCode),
    );
    return formatter.format(amount.toDouble());
  }

  static String formatPercent(Decimal value, {int decimalDigits = 2}) {
    final sign = value >= Decimal.zero ? '+' : '';
    return '$sign${value.toStringAsFixed(decimalDigits)}%';
  }

  static String _symbol(String code) {
    const symbols = {
      'EUR': '€',
      'USD': '\$',
      'GBP': '£',
      'JPY': '¥',
      'CHF': 'CHF ',
      'CAD': 'CA\$',
      'AUD': 'A\$',
    };
    return symbols[code] ?? '$code ';
  }
}
