import 'package:decimal/decimal.dart';
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
    this.trailingStopPct,
    this.trailingStopHighWater,
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
  // Trailing stop-loss — null means not configured.
  // trailingStopPct is the drop threshold in percent (e.g. 10 = −10%).
  // trailingStopHighWater is the peak price recorded since the alert was set.
  final Decimal? trailingStopPct;
  final Decimal? trailingStopHighWater;

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
    Object? trailingStopPct = _absent,
    Object? trailingStopHighWater = _absent,
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
        trailingStopPct: trailingStopPct == _absent
            ? this.trailingStopPct
            : trailingStopPct as Decimal?,
        trailingStopHighWater: trailingStopHighWater == _absent
            ? this.trailingStopHighWater
            : trailingStopHighWater as Decimal?,
      );

  @override
  List<Object?> get props => [
        id,
        brokerId,
        isin,
        symbol,
        name,
        exchange,
        currency,
        dripEnabled,
        assetType,
        trailingStopPct,
        trailingStopHighWater,
      ];
}

const _absent = Object();
