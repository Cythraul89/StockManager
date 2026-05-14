import 'package:equatable/equatable.dart';

class Stock extends Equatable {
  const Stock({
    required this.id,
    required this.brokerId,
    required this.isin,
    required this.symbol,
    required this.name,
    required this.exchange,
    required this.currency,
    required this.dripEnabled,
  });

  final String id;
  final String brokerId;
  final String isin;
  final String symbol;
  final String name;
  final String exchange;
  final String currency;
  final bool dripEnabled;

  Stock copyWith({
    String? id,
    String? brokerId,
    String? isin,
    String? symbol,
    String? name,
    String? exchange,
    String? currency,
    bool? dripEnabled,
  }) =>
      Stock(
        id: id ?? this.id,
        brokerId: brokerId ?? this.brokerId,
        isin: isin ?? this.isin,
        symbol: symbol ?? this.symbol,
        name: name ?? this.name,
        exchange: exchange ?? this.exchange,
        currency: currency ?? this.currency,
        dripEnabled: dripEnabled ?? this.dripEnabled,
      );

  @override
  List<Object?> get props =>
      [id, brokerId, isin, symbol, name, exchange, currency, dripEnabled];
}
