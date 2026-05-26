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
    this.isEstimated = false,
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
  /// True when pricePerShare was estimated from historic closing price rather
  /// than read directly from the CSV.
  final bool isEstimated;
}

/// An executed EUR-unit order (KVG market order, Bruchstücke) whose CSV row
/// carries the invested EUR amount but no execution price per share.  The
/// import screen can offer to resolve this by fetching the historic closing
/// price and deriving shares = investedAmount ÷ price.
class FlatexUnpricedOrder {
  const FlatexUnpricedOrder({
    required this.isin,
    required this.name,
    required this.isBuy,
    required this.assetType,
    required this.executedAt,
    required this.investedAmount,
    required this.orderNumber,
  });

  final String isin;
  final String name;
  final bool isBuy;
  final AssetType assetType;
  final DateTime executedAt;
  /// The invested EUR amount from col 8 (Menge) when unit = EUR.
  final Decimal investedAmount;
  final String orderNumber;
}

class FlatexParseResult {
  const FlatexParseResult({
    required this.importable,
    required this.unpricedOrders,
    required this.skippedNotExecuted,
    required this.skippedFractional,
    required this.skippedNoPrice,
    this.skippedOther = 0,
  });

  final List<FlatexParsedOrder> importable;
  /// EUR-unit orders with no execution price in the CSV.  Share count can be
  /// estimated from the historic closing price on the order date.
  final List<FlatexUnpricedOrder> unpricedOrders;
  final int skippedNotExecuted;
  final int skippedFractional;
  final int skippedNoPrice;
  /// Rows dropped for other reasons: bad ISIN format, unparseable date,
  /// zero/missing quantity, or fewer than 10 columns.
  final int skippedOther;

  int get total =>
      importable.length +
      unpricedOrders.length +
      skippedNotExecuted +
      skippedFractional +
      skippedNoPrice +
      skippedOther;
}

/// Parses the Flatex "Orders" CSV export (semicolon-delimited, Latin-1 encoding).
///
/// The [csvContent] must already be decoded from Latin-1 bytes so that
/// German umlauts (ü, ä, ö) are proper Unicode characters.
///
/// Imported row types:
///   - Executed limit / stop-market orders (price from col 12)
///   - KVG savings-plan and Bruchstücke rows (price from col 10 Ausführungspreis,
///     which equals total_amount / shares; col 12 Limit is empty)
///   - EUR-unit rows: shares derived from invested amount ÷ execution price
///
/// Unpriced (returned in [FlatexParseResult.unpricedOrders]):
///   - EUR-unit (KVG market) orders where Flatex records the invested amount
///     but no per-share price.  The caller may resolve these by fetching the
///     historic closing price and recomputing shares.
///
/// Skipped: non-executed orders, rows with no unit, and non-EUR rows where no
/// price can be determined from cols 12, 10, or 14.
///
/// **Currency note:** the limit price currency is taken from the column after
/// the limit price (col 13).  Col 11 sometimes holds an order-type keyword
/// ("Limit", "Market", "Stop") instead of a currency code and is validated
/// before use.  Stop-market orders without a limit have their price stored with
/// the default `'EUR'` currency.
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
  static const _colExecPrice = 10; // Ausführungspreis — filled for KVG/NAV rows
  static const _colExecCcy = 11;   // Ausführungswährung (or order-type keyword)
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
        unpricedOrders: [],
        skippedNotExecuted: 0,
        skippedFractional: 0,
        skippedNoPrice: 0,
      );
    }

    final importable = <FlatexParsedOrder>[];
    final unpricedOrders = <FlatexUnpricedOrder>[];
    var skippedNotExecuted = 0;
    var skippedFractional = 0;
    var skippedNoPrice = 0;
    var skippedOther = 0;

    // Skip header row (index 0)
    for (var i = 1; i < lines.length; i++) {
      final cols = lines[i].split(';');
      if (cols.length < 10) { skippedOther++; continue; }

      final status = cols[_colStatus].trim();
      if (!_isExecuted(status)) {
        skippedNotExecuted++;
        continue;
      }

      final unit = cols[_colUnit].trim();
      final venue = cols[_colVenue].trim();

      if (_isFractional(unit, venue)) {
        skippedFractional++;
        continue;
      }

      final isinWkn = cols[_colIsinWkn].trim();
      final isin = isinWkn.contains('/')
          ? isinWkn.split('/').first.trim()
          : isinWkn;
      if (isin.isEmpty || isin.length != 12) { skippedOther++; continue; }

      // menge is either a share count (unit=Stück) or an invested EUR amount
      // (unit=EUR); the shares calculation below handles both cases.
      final mengeDecimal = _parseGermanDecimal(cols[_colMenge].trim());
      if (mengeDecimal == null || mengeDecimal <= Decimal.zero) {
        skippedOther++;
        continue;
      }

      // Parse date early so it is available for both the priced and unpriced paths.
      final executedAt = _parseDateTime(cols[_colDateTime].trim());
      if (executedAt == null) { skippedOther++; continue; }

      // Price priority:
      //   1. Limit (col 12) + currency (col 13) — regular limit/stop orders
      //   2. Ausführungspreis (col 10) + currency (col 11) — KVG/NAV and
      //      Bruchstücke rows where no limit was set; the execution price equals
      //      total_amount / shares (the NAV price Flatex filled the order at)
      //   3. Stop (col 14) — stop-market orders
      Decimal? price;
      var currency = 'EUR';
      final limitStr =
          cols.length > _colLimit ? cols[_colLimit].trim() : '';
      if (limitStr.isNotEmpty) {
        price = _parseGermanDecimal(limitStr);
        if (cols.length > _colLimitCcy && cols[_colLimitCcy].trim().isNotEmpty) {
          currency = cols[_colLimitCcy].trim();
        }
      }
      if (price == null && cols.length > _colExecPrice) {
        final execStr = cols[_colExecPrice].trim();
        if (execStr.isNotEmpty) {
          price = _parseGermanDecimal(execStr);
          if (cols.length > _colExecCcy) {
            final ccyStr = cols[_colExecCcy].trim();
            // Guard: col 11 sometimes holds the order type ("Limit", "Market",
            // "Stop") rather than a currency code. Only accept it when it looks
            // like an ISO 4217 code (exactly 3 uppercase ASCII letters).
            if (_isCurrencyCode(ccyStr)) currency = ccyStr;
          }
        }
      }
      if (price == null && cols.length > _colStop) {
        final stopStr = cols[_colStop].trim();
        if (stopStr.isNotEmpty) price = _parseGermanDecimal(stopStr);
      }

      if (price == null || price <= Decimal.zero) {
        // EUR-unit rows (KVG market orders) carry the invested amount but no
        // per-share price.  Surface them as unpricedOrders so the screen can
        // offer estimation from historic closing price.
        if (unit == 'EUR') {
          unpricedOrders.add(FlatexUnpricedOrder(
            isin: isin,
            name: cols[_colName].trim(),
            isBuy: cols[_colArt].trim() == 'Kauf',
            assetType: _assetType(cols[_colKategorie].trim()),
            executedAt: executedAt,
            investedAmount: mengeDecimal,
            orderNumber: cols[_colOrderNr].trim(),
          ));
        } else {
          skippedNoPrice++;
        }
        continue;
      }

      // EUR-unit rows (Bruchstücke etc.): menge is the invested EUR amount;
      // derive share count from amount ÷ execution price.
      // Guard: if the exec currency is not EUR we can't divide EUR by a
      // foreign-currency price — skip rather than import a wrong share count.
      if (unit == 'EUR' && currency != 'EUR') {
        skippedNoPrice++;
        continue;
      }
      final Decimal shares;
      if (unit == 'EUR') {
        shares = (mengeDecimal.toRational() / price.toRational())
            .toDecimal(scaleOnInfinitePrecision: 8);
      } else {
        shares = mengeDecimal;
      }
      if (shares <= Decimal.zero) { skippedOther++; continue; }

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
      unpricedOrders: unpricedOrders,
      skippedNotExecuted: skippedNotExecuted,
      skippedFractional: skippedFractional,
      skippedNoPrice: skippedNoPrice,
      skippedOther: skippedOther,
    );
  }

  // "Ausgeführt" in both Latin-1-decoded and any encoding variant.
  static bool _isExecuted(String status) =>
      status.startsWith('Ausgef') && status.endsWith('hrt');

  // Only skip rows where we genuinely have no share count AND no way to derive one:
  // empty unit with no EUR amount. All EUR-unit rows (KVG, Bruchstücke, etc.)
  // are handled by the amount ÷ price calculation in the main loop.
  static bool _isFractional(String unit, String venue) => unit.isEmpty;

  // Returns true only for strings that look like ISO 4217 currency codes
  // (exactly 3 uppercase ASCII letters). This guards against Flatex rows where
  // col 11 contains an order-type keyword ("Limit", "Market", "Stop") instead
  // of a currency.
  static bool _isCurrencyCode(String s) =>
      s.length == 3 &&
      s.codeUnits.every((c) => c >= 0x41 && c <= 0x5A); // A–Z

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
    // Flatex uses "DD.MM.YYYY / HH:MM:SS" but some order types (e.g. KVG
    // savings plans) may omit the time or use a plain space as separator.
    // Try " / " first, fall back to first-space split, then date-only.
    String datePart;
    String? timePart;

    final slashIdx = s.indexOf(' / ');
    if (slashIdx > 0) {
      datePart = s.substring(0, slashIdx);
      timePart = s.substring(slashIdx + 3);
    } else {
      final spaceIdx = s.indexOf(' ');
      if (spaceIdx > 0) {
        datePart = s.substring(0, spaceIdx);
        timePart = s.substring(spaceIdx + 1);
      } else {
        datePart = s; // date only
      }
    }

    final d = datePart.split('.');
    if (d.length != 3) return null;
    try {
      final year  = int.parse(d[2]);
      final month = int.parse(d[1]);
      final day   = int.parse(d[0]);

      if (timePart != null && timePart.isNotEmpty) {
        final t = timePart.split(':');
        return DateTime(
          year, month, day,
          int.parse(t[0]),
          t.length > 1 ? int.parse(t[1]) : 0,
          t.length > 2 ? int.parse(t[2]) : 0,
        );
      }
      return DateTime(year, month, day);
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
