import 'package:decimal/decimal.dart';

class FetchedDividend {
  const FetchedDividend({
    required this.date,
    required this.amountPerShare,
    required this.isPaid,
  });

  final DateTime date;
  final Decimal amountPerShare;
  // false = upcoming expected dividend
  final bool isPaid;
}
