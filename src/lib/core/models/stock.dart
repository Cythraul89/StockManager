import 'package:equatable/equatable.dart';

import 'asset_type.dart';

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
    this.assetType = AssetType.stock,
  });

  final String id;
  final String brokerId;
  final String isin;
  final String symbol;
  final String name;
  final String exchange;
  final String currency;
  final bool dripEnabled;
  final AssetType assetType;

  Stock copyWith({
    String? id,
    String? brokerId,
    String? isin,
    String? symbol,
    String? name,
    String? exchange,
    String? currency,
    bool? dripEnabled,
    AssetType? assetType,
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
        assetType: assetType ?? this.assetType,
      );

  @override
  List<Object?> get props =>
      [id, brokerId, isin, symbol, name, exchange, currency, dripEnabled, assetType];
}
