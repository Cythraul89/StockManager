import 'package:decimal/decimal.dart';

import '../../../core/models/asset_type.dart';

class FlatexParsedOrder {
  const FlatexParsedOrder({
    required this.isin,
    required this.name,
    required this.isBuy,
    required this.assetType,
    required this.executedAt,
    required this.shares,
    required this.pricePerShare,
    required this.currency,
    required this.orderNumber,
  });

  final String isin;
  final String name;
  final bool isBuy;
  final AssetType assetType;
  final DateTime executedAt;
  final Decimal shares;
  final Decimal pricePerShare;
  final String currency;
  final String orderNumber;
}

class FlatexParseResult {
  const FlatexParseResult({
    required this.importable,
    required this.skippedNotExecuted,
    required this.skippedFractional,
    required this.skippedNoPrice,
  });

  final List<FlatexParsedOrder> importable;
  final int skippedNotExecuted;
  final int skippedFractional;
  final int skippedNoPrice;

  int get total =>
      importable.length +
      skippedNotExecuted +
      skippedFractional +
      skippedNoPrice;
}

/// Parses the Flatex "Orders" CSV export (semicolon-delimited, Latin-1 encoding).
///
/// The [csvContent] must already be decoded from Latin-1 bytes so that
/// German umlauts (ü, ä, ö) are proper Unicode characters.
///
/// Imported row types:
///   - Executed limit orders with a Stück quantity
///   - Executed stop-market orders with a Stück quantity
///   - KVG savings-plan orders (venue == "KVG", unit == "EUR"):
///     shares are derived from the invested EUR amount divided by the NAV price
///
/// Skipped: non-executed orders, Bruchstücke (fractional-fill) rows, and any
/// row where a price cannot be determined.
///
/// **Currency note:** the limit price currency is taken from the column after
/// the limit price. Stop-market orders (no limit, only a stop column) have no
/// accompanying currency column in the Flatex CSV; their price is stored with
/// the default `'EUR'` currency. For non-EUR stop orders this will be wrong.
class FlatexOrderParser {
  // Column indices (0-based) in the Flatex orders CSV
  static const _colKategorie = 0;
  static const _colName = 1;
  static const _colIsinWkn = 2;
  static const _colArt = 3;
  static const _colVenue = 4;
  static const _colOrderNr = 5;
  static const _colDateTime = 6;
  static const _colStatus = 7;
  static const _colMenge = 8;
  static const _colUnit = 9;
  static const _colLimit = 12;
  static const _colLimitCcy = 13;
  static const _colStop = 14;

  static FlatexParseResult parse(String csvContent) {
    final lines = csvContent
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();

    if (lines.length < 2) {
      return const FlatexParseResult(
        importable: [],
        skippedNotExecuted: 0,
        skippedFractional: 0,
        skippedNoPrice: 0,
      );
    }

    final importable = <FlatexParsedOrder>[];
    var skippedNotExecuted = 0;
    var skippedFractional = 0;
    var skippedNoPrice = 0;

    // Skip header row (index 0)
    for (var i = 1; i < lines.length; i++) {
      final cols = lines[i].split(';');
      if (cols.length < 13) continue;

      final status = cols[_colStatus].trim();
      if (!_isExecuted(status)) {
        skippedNotExecuted++;
        continue;
      }

      final unit = cols[_colUnit].trim();
      final venue = cols[_colVenue].trim();
      final isKvg = venue == 'KVG';

      if (_isFractional(unit, venue)) {
        skippedFractional++;
        continue;
      }

      final isinWkn = cols[_colIsinWkn].trim();
      final isin = isinWkn.contains('/')
          ? isinWkn.split('/').first.trim()
          : isinWkn;
      if (isin.isEmpty || isin.length != 12) continue;

      // KVG: menge column holds the invested EUR amount, not a share count.
      // Regular rows: menge column holds the share count directly.
      final mengeDecimal = _parseGermanDecimal(cols[_colMenge].trim());
      if (mengeDecimal == null || mengeDecimal <= Decimal.zero) continue;

      // Determine price: prefer limit price, fall back to stop price.
      Decimal? price;
      var currency = 'EUR';
      final limitStr = cols[_colLimit].trim();
      if (limitStr.isNotEmpty) {
        price = _parseGermanDecimal(limitStr);
        if (cols.length > _colLimitCcy && cols[_colLimitCcy].trim().isNotEmpty) {
          currency = cols[_colLimitCcy].trim();
        }
      }
      if (price == null && cols.length > _colStop) {
        final stopStr = cols[_colStop].trim();
        if (stopStr.isNotEmpty) price = _parseGermanDecimal(stopStr);
      }
      if (price == null || price <= Decimal.zero) {
        skippedNoPrice++;
        continue;
      }

      // For KVG rows derive share count from EUR amount ÷ NAV price.
      final Decimal shares;
      if (isKvg && unit == 'EUR') {
        shares = (mengeDecimal.toRational() / price.toRational())
            .toDecimal(scaleOnInfinitePrecision: 8);
      } else {
        shares = mengeDecimal;
      }
      if (shares <= Decimal.zero) continue;

      final executedAt = _parseDateTime(cols[_colDateTime].trim());
      if (executedAt == null) continue;

      importable.add(FlatexParsedOrder(
        isin: isin,
        name: cols[_colName].trim(),
        isBuy: cols[_colArt].trim() == 'Kauf',
        assetType: _assetType(cols[_colKategorie].trim()),
        executedAt: executedAt,
        shares: shares,
        pricePerShare: price,
        currency: currency,
        orderNumber: cols[_colOrderNr].trim(),
      ));
    }

    return FlatexParseResult(
      importable: importable,
      skippedNotExecuted: skippedNotExecuted,
      skippedFractional: skippedFractional,
      skippedNoPrice: skippedNoPrice,
    );
  }

  // "Ausgeführt" in both Latin-1-decoded and any encoding variant.
  static bool _isExecuted(String status) =>
      status.startsWith('Ausgef') && status.endsWith('hrt');

  // Bruchstücke (partial-fill fractional rows): unit is EUR on non-KVG rows,
  // or venue explicitly says Bruchstücke.  KVG savings-plan rows (venue == 'KVG')
  // also have unit == 'EUR' but ARE imported — shares are derived from amount ÷ price.
  static bool _isFractional(String unit, String venue) {
    if (venue == 'KVG') return false;
    return unit == 'EUR' || unit.isEmpty || venue.toLowerCase().contains('bruchst');
  }

  static Decimal? _parseGermanDecimal(String s) {
    if (s.isEmpty) return null;
    // German format: 1.000,50 → 1000.50
    final normalized = s.replaceAll('.', '').replaceAll(',', '.');
    try {
      return Decimal.parse(normalized);
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseDateTime(String s) {
    // Format: DD.MM.YYYY / HH:MM:SS
    final parts = s.split(' / ');
    if (parts.length != 2) return null;
    final d = parts[0].split('.');
    final t = parts[1].split(':');
    if (d.length != 3 || t.length != 3) return null;
    try {
      return DateTime(
        int.parse(d[2]),
        int.parse(d[1]),
        int.parse(d[0]),
        int.parse(t[0]),
        int.parse(t[1]),
        int.parse(t[2]),
      );
    } catch (_) {
      return null;
    }
  }

  static AssetType _assetType(String kategorie) =>
      switch (kategorie.toLowerCase()) {
        'etf' => AssetType.etf,
        'etc' => AssetType.etc,
        'aktie' => AssetType.stock,
        _ => AssetType.other,
      };
}
