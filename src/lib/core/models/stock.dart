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
    this.manualYieldPct,
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
  // Manual annual yield/interest override in percent (e.g. 6.36 = 6.36% p.a.).
  // Used for fixed-income assets that pay interest rather than dividends.
  final Decimal? manualYieldPct;

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
    Object? manualYieldPct = _absent,
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
        manualYieldPct: manualYieldPct == _absent
            ? this.manualYieldPct
            : manualYieldPct as Decimal?,
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
        manualYieldPct,
      ];
}

const _absent = Object();
