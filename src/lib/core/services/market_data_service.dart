import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/analyst_data.dart';
import '../models/fetched_dividend.dart';
import '../models/price_quote.dart';

class MarketDataService {
  MarketDataService(this._dio);

  final Dio _dio;

  static const _yahooBaseUrl =
      'https://query1.finance.yahoo.com/v8/finance/chart/';
  static const _yahooQuoteSummaryUrl =
      'https://query1.finance.yahoo.com/v11/finance/quoteSummary/';
  static const _stooqBaseUrl = 'https://stooq.com/q/l/';
  static const _stooqHistUrl = 'https://stooq.com/q/d/l/';

  Future<PriceQuote?> fetchQuote(
    String symbol,
    String stockId, {
    String? stockCurrency,
  }) async {
    final yahoo = await _fetchFromYahoo(symbol, stockId);
    if (yahoo != null) return yahoo;

    // Stooq fallback — no API key required; does not return currency, so
    // stockCurrency must be provided to use it.
    if (stockCurrency != null) {
      return _fetchFromStooq(symbol, stockId, stockCurrency);
    }
    return null;
  }

  Future<Map<String, PriceQuote>> fetchQuotes(
    Map<String, String> symbolByStockId, {
    Map<String, String> currencyByStockId = const {},
  }) async {
    final results = <String, PriceQuote>{};
    final entries = symbolByStockId.entries.toList();

    for (var i = 0; i < entries.length; i += 10) {
      final batch = entries.skip(i).take(10);
      final futures = batch.map((e) => fetchQuote(
            e.value,
            e.key,
            stockCurrency: currencyByStockId[e.key],
          ));
      final quotes = await Future.wait(futures);
      for (final q in quotes) {
        if (q != null) results[q.stockId] = q;
      }
    }
    return results;
  }

  /// Returns the closing price for [date], or the current quote if [date] is
  /// today.  Returns null when no data is available (weekend, holiday, unknown
  /// symbol).
  Future<Decimal?> fetchHistoricalPrice(
    String symbol,
    DateTime date, {
    String? stockCurrency,
  }) async {
    final today = DateTime.now();
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    if (isToday) {
      final quote = await fetchQuote(symbol, '', stockCurrency: stockCurrency);
      return quote?.price;
    }

    final price = await _fetchHistoricalFromYahoo(symbol, date);
    if (price != null) return price;

    return _fetchHistoricalFromStooq(symbol, date);
  }

  /// Fetches analyst consensus data (target price range + recommendation) from
  /// Yahoo Finance quoteSummary/financialData.  Returns null when unavailable.
  Future<AnalystData?> fetchAnalystData(String symbol) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_yahooQuoteSummaryUrl$symbol',
        queryParameters: {'modules': 'financialData'},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final result =
          (response.data?['quoteSummary']?['result'] as List?)?.firstOrNull
              as Map<String, dynamic>?;
      if (result == null) return null;

      final fd = result['financialData'] as Map<String, dynamic>?;
      if (fd == null) return null;

      final meanRaw = (fd['targetMeanPrice'] as Map<String, dynamic>?)?['raw'];
      if (meanRaw == null) return null;

      final lowRaw = (fd['targetLowPrice'] as Map<String, dynamic>?)?['raw'];
      final highRaw = (fd['targetHighPrice'] as Map<String, dynamic>?)?['raw'];
      final recKey = fd['recommendationKey'] as String?;
      final numRaw =
          (fd['numberOfAnalystOpinions'] as Map<String, dynamic>?)?['raw'];
      final currency = fd['financialCurrency'] as String?;

      return AnalystData(
        targetMeanPrice: Decimal.parse(meanRaw.toString()),
        targetLowPrice:
            lowRaw != null ? Decimal.parse(lowRaw.toString()) : null,
        targetHighPrice:
            highRaw != null ? Decimal.parse(highRaw.toString()) : null,
        recommendationKey: recKey?.isNotEmpty == true ? recKey : null,
        numberOfAnalysts: numRaw is int ? numRaw : null,
        currency: currency,
      );
    } on DioException {
      return null;
    } catch (e) {
      debugPrint('MarketDataService: analyst data fetch failed for $symbol: $e');
      return null;
    }
  }

  /// Fetches dividend history (paid, up to 5 years) and the next expected
  /// dividend (if any) from Yahoo Finance.  Returns an empty list when the
  /// symbol is unknown or the API is unreachable.
  Future<List<FetchedDividend>> fetchDividends(String symbol) async {
    final paid = await _fetchPaidDividendsFromYahoo(symbol);
    final expected = await _fetchExpectedDividendFromYahoo(symbol, paid);
    return [...paid, if (expected != null) expected];
  }

  Future<PriceQuote?> _fetchFromYahoo(String symbol, String stockId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_yahooBaseUrl$symbol',
        queryParameters: {'interval': '1d', 'range': '1d'},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final chart = response.data?['chart'] as Map<String, dynamic>?;
      final result =
          (chart?['result'] as List?)?.firstOrNull as Map<String, dynamic>?;
      if (result == null) return null;

      final meta = result['meta'] as Map<String, dynamic>?;
      final price = meta?['regularMarketPrice'];
      final currency = meta?['currency'] as String?;

      if (price == null || currency == null) return null;

      return PriceQuote(
        stockId: stockId,
        price: Decimal.parse(price.toString()),
        currency: currency,
        fetchedAt: DateTime.now(),
      );
    } on DioException {
      return null;
    }
  }

  Future<PriceQuote?> _fetchFromStooq(
      String symbol, String stockId, String currency) async {
    try {
      final response = await _dio.get<String>(
        _stooqBaseUrl,
        queryParameters: {'s': symbol, 'f': 'sdc', 'e': 'csv'},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          responseType: ResponseType.plain,
        ),
      );

      final body = response.data;
      if (body == null) return null;

      final lines = body.trim().split('\n');
      if (lines.length < 2) return null;

      // CSV: Symbol,Date,Close
      final values = lines[1].split(',');
      if (values.length < 3) return null;

      final closeStr = values[2].trim();
      if (closeStr == 'N/D' || closeStr == 'N/A' || closeStr.isEmpty) {
        return null;
      }

      final close = Decimal.tryParse(closeStr);
      if (close == null || close == Decimal.zero) return null;

      return PriceQuote(
        stockId: stockId,
        price: close,
        currency: currency,
        fetchedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('MarketDataService: Stooq fetch failed for $symbol: $e');
      return null;
    }
  }

  Future<Decimal?> _fetchHistoricalFromYahoo(
      String symbol, DateTime date) async {
    try {
      final utc = DateTime.utc(date.year, date.month, date.day);
      final period1 = utc.millisecondsSinceEpoch ~/ 1000;
      final period2 =
          utc.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;

      final response = await _dio.get<Map<String, dynamic>>(
        '$_yahooBaseUrl$symbol',
        queryParameters: {
          'interval': '1d',
          'period1': period1,
          'period2': period2,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final chart = response.data?['chart'] as Map<String, dynamic>?;
      final result =
          (chart?['result'] as List?)?.firstOrNull as Map<String, dynamic>?;
      if (result == null) return null;

      final quotes = result['indicators']?['quote'] as List?;
      final closes =
          (quotes?.firstOrNull as Map<String, dynamic>?)?['close'] as List?;
      // Use the last non-null close in the window (handles partial trading days).
      final close =
          closes?.reversed.firstWhere((c) => c != null, orElse: () => null);
      if (close != null) return Decimal.parse(close.toString());

      return null;
    } on DioException {
      return null;
    }
  }

  Future<Decimal?> _fetchHistoricalFromStooq(
      String symbol, DateTime date) async {
    try {
      final d = '${date.year}'
          '${date.month.toString().padLeft(2, '0')}'
          '${date.day.toString().padLeft(2, '0')}';

      final response = await _dio.get<String>(
        _stooqHistUrl,
        queryParameters: {'s': symbol, 'd1': d, 'd2': d, 'i': 'd'},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          responseType: ResponseType.plain,
        ),
      );

      final body = response.data;
      if (body == null) return null;

      final lines = body.trim().split('\n');
      if (lines.length < 2) return null;

      // CSV: Date,Open,High,Low,Close,Volume
      final values = lines[1].split(',');
      if (values.length < 5) return null;

      final closeStr = values[4].trim();
      if (closeStr == 'N/D' || closeStr == 'N/A' || closeStr.isEmpty) {
        return null;
      }

      return Decimal.tryParse(closeStr);
    } catch (e) {
      debugPrint(
          'MarketDataService: Stooq historical fetch failed for $symbol: $e');
      return null;
    }
  }

  Future<List<FetchedDividend>> _fetchPaidDividendsFromYahoo(
      String symbol) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_yahooBaseUrl$symbol',
        queryParameters: {
          'events': 'dividends',
          'interval': '1mo',
          'range': '5y',
        },
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final chart = response.data?['chart'] as Map<String, dynamic>?;
      final result =
          (chart?['result'] as List?)?.firstOrNull as Map<String, dynamic>?;
      if (result == null) return [];

      final events = result['events'] as Map<String, dynamic>?;
      final dividendsMap = events?['dividends'] as Map<String, dynamic>?;
      if (dividendsMap == null || dividendsMap.isEmpty) return [];

      final fetched = <FetchedDividend>[];
      for (final entry in dividendsMap.values) {
        if (entry is! Map<String, dynamic>) continue;
        final amount = entry['amount'];
        final timestamp = entry['date'];
        if (amount == null || timestamp == null) continue;

        final utc = DateTime.fromMillisecondsSinceEpoch(
            (timestamp as int) * 1000,
            isUtc: true);
        final amountDecimal = Decimal.tryParse(amount.toString());
        if (amountDecimal == null || amountDecimal <= Decimal.zero) continue;

        fetched.add(FetchedDividend(
          date: DateTime(utc.year, utc.month, utc.day),
          amountPerShare: amountDecimal,
          isPaid: true,
        ));
      }
      return fetched;
    } on DioException {
      return [];
    }
  }

  Future<FetchedDividend?> _fetchExpectedDividendFromYahoo(
      String symbol, List<FetchedDividend> recentPaid) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_yahooQuoteSummaryUrl$symbol',
        queryParameters: {'modules': 'calendarEvents'},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final result =
          (response.data?['quoteSummary']?['result'] as List?)?.firstOrNull
              as Map<String, dynamic>?;
      if (result == null) return null;

      final calEvents = result['calendarEvents'] as Map<String, dynamic>?;
      final divDateRaw =
          (calEvents?['dividendDate'] as Map<String, dynamic>?)?['raw'];
      if (divDateRaw == null) return null;

      final utc = DateTime.fromMillisecondsSinceEpoch(
          (divDateRaw as int) * 1000,
          isUtc: true);
      final divDate = DateTime(utc.year, utc.month, utc.day);

      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      if (!divDate.isAfter(todayDate)) return null;

      // Use the most recent paid dividend amount as estimate for expected
      if (recentPaid.isEmpty) return null;
      final lastPaid =
          recentPaid.reduce((a, b) => a.date.isAfter(b.date) ? a : b);

      return FetchedDividend(
        date: divDate,
        amountPerShare: lastPaid.amountPerShare,
        isPaid: false,
      );
    } on DioException {
      return null;
    } catch (e) {
      debugPrint(
          'MarketDataService: expected dividend fetch failed for $symbol: $e');
      return null;
    }
  }
}
