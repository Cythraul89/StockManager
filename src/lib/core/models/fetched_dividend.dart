import 'package:decimal/decimal.dart';

class FetchedDividend {
  const FetchedDividend({
    required this.date,
    required this.amountPerShare,
    required this.currency,
    required this.isPaid,
  });

  final DateTime date;
  final Decimal amountPerShare;
  // Currency of the amount as returned by the data source (e.g. "NOK", "GBP").
  final String currency;
  // false = upcoming expected dividend
  final bool isPaid;
}
