import 'package:cookie_jar/cookie_jar.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';

import '../models/analyst_data.dart';
import '../models/fetched_dividend.dart';
import '../models/price_quote.dart';

class MarketDataService {
  MarketDataService(this._dio) {
    _cookieJar = CookieJar();
    // Dedicated Dio instance for authenticated Yahoo Finance requests.
    // The CookieManager stores cookies from every response (including
    // redirects) automatically — required for the EU GDPR consent flow.
    _yahooDio = Dio(BaseOptions(
      headers: {
        'User-Agent': _userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
      },
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ))..interceptors.add(CookieManager(_cookieJar));
  }

  final Dio _dio;
  late final CookieJar _cookieJar;
  late final Dio _yahooDio;

  static const _yahooBaseUrl =
      'https://query1.finance.yahoo.com/v8/finance/chart/';
  static const _yahooQuoteSummaryUrl =
      'https://query2.finance.yahoo.com/v11/finance/quoteSummary/';
  static const _stooqBaseUrl = 'https://stooq.com/q/l/';
  static const _stooqHistUrl = 'https://stooq.com/q/d/l/';

  static const _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0';

  // Crumb is required as a query param on quoteSummary calls. Cached 55 min.
  String? _crumb;
  DateTime? _sessionInitAt;

  /// Ensures a valid Yahoo Finance session (crumb).
  /// The cookie jar on [_yahooDio] handles all cookie management, including
  /// the EU GDPR consent redirect, automatically.
  Future<void> _ensureSession() async {
    if (_crumb != null &&
        _sessionInitAt != null &&
        DateTime.now().difference(_sessionInitAt!).inMinutes < 55) {
      return;
    }

    try {
      // Step 1: visit Yahoo Finance. EU users are redirected to the GDPR
      // consent page; the cookie jar stores cookies from every hop.
      final homeResp = await _yahooDio.get<String>(
        'https://finance.yahoo.com/',
        options: Options(responseType: ResponseType.plain),
      );

      final body = homeResp.data ?? '';
      debugPrint(
          'MarketDataService: homepage status=${homeResp.statusCode} '
          'body_len=${body.length} '
          'has_csrfToken=${body.contains('csrfToken')}');

      // EU/GDPR: if we landed on the consent page, submit acceptance.
      if (body.contains('csrfToken')) {
        final csrfToken = _extractHidden(body, 'csrfToken');
        final sessionId = _extractHidden(body, 'sessionId');
        final originalDoneUrl = _extractHidden(body, 'originalDoneUrl');
        debugPrint('MarketDataService: GDPR consent page — '
            'csrfToken=${csrfToken != null} sessionId=${sessionId != null}');

        if (csrfToken != null && sessionId != null) {
          final payload = [
            'csrfToken=${Uri.encodeComponent(csrfToken)}',
            'sessionId=${Uri.encodeComponent(sessionId)}',
            if (originalDoneUrl != null)
              'originalDoneUrl=${Uri.encodeComponent(originalDoneUrl)}',
            'namespace=yahoo',
            'agree=agree',
            'agree=agree',
          ].join('&');

          // Do NOT auto-follow the redirect: Yahoo sets the session cookies
          // in the 302 response's Set-Cookie headers. The CookieManager
          // only sees the final response when Dio auto-follows, so those
          // cookies would be lost. By disabling redirect-following here the
          // interceptor captures the 302 cookies, then we follow manually.
          final consentResp = await _yahooDio.post<String>(
            'https://consent.yahoo.com/v2/collectConsent',
            data: payload,
            options: Options(
              contentType: 'application/x-www-form-urlencoded',
              responseType: ResponseType.plain,
              followRedirects: false,
              validateStatus: (s) => s != null && s < 400,
            ),
          );
          debugPrint('MarketDataService: consent POST '
              'status=${consentResp.statusCode}');

          // Follow the redirect so the cookie jar also captures any
          // yahoo.com session cookies set by finance.yahoo.com.
          final location = consentResp.headers['location']?.first;
          if (location != null) {
            await _yahooDio.get<void>(
              location,
              options: Options(
                followRedirects: true,
                validateStatus: (s) => s != null && s < 400,
              ),
            );
          }
        }
      }

      // Log what cookies the jar holds for the query2 domain.
      final jarCookies = await _cookieJar.loadForRequest(
          Uri.parse('https://query2.finance.yahoo.com/'));
      debugPrint(
          'MarketDataService: jar has ${jarCookies.length} cookies for '
          'query2.finance.yahoo.com: '
          '${jarCookies.map((c) => c.name).toList()}');

      // Step 2: fetch the crumb — cookie jar sends the right session cookies.
      final crumbResp = await _yahooDio.get<String>(
        'https://query2.finance.yahoo.com/v1/test/getcrumb',
        options: Options(responseType: ResponseType.plain),
      );
      final crumb = crumbResp.data?.trim();
      debugPrint('MarketDataService: crumb response '
          'status=${crumbResp.statusCode} crumb="$crumb"');
      if (crumb != null && crumb.isNotEmpty && !crumb.startsWith('{')) {
        _crumb = crumb;
        _sessionInitAt = DateTime.now();
        debugPrint('MarketDataService: session established, crumb set');
      }
    } catch (e) {
      debugPrint('MarketDataService: Yahoo session init failed: $e');
    }
  }

  Map<String, dynamic> _quoteSummaryParams(Map<String, dynamic> base) => {
        ...base,
        if (_crumb != null) 'crumb': _crumb!,
      };

  Future<PriceQuote?> fetchQuote(
    String symbol,
    String stockId, {
    String? stockCurrency,
  }) async {
    final yahoo = await _fetchFromYahoo(symbol, stockId);
    if (yahoo != null) { return yahoo; }

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
        if (q != null) { results[q.stockId] = q; }
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
    if (price != null) { return price; }

    return _fetchHistoricalFromStooq(symbol, date);
  }

  /// Fetches analyst consensus data (target price range + recommendation) from
  /// Yahoo Finance quoteSummary/financialData.  Returns null when unavailable.
  Future<AnalystData?> fetchAnalystData(String symbol) async {
    await _ensureSession();
    try {
      final response = await _yahooDio.get<Map<String, dynamic>>(
        '$_yahooQuoteSummaryUrl$symbol',
        queryParameters: _quoteSummaryParams({'modules': 'financialData'}),
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      debugPrint('MarketDataService: quoteSummary status=${response.statusCode} '
          'keys=${response.data?.keys.toList()}');
      final result =
          (response.data?['quoteSummary']?['result'] as List?)?.firstOrNull
              as Map<String, dynamic>?;
      if (result == null) {
        debugPrint('MarketDataService: quoteSummary result=null, '
            'error=${response.data?['quoteSummary']?['error']}');
        return null;
      }

      final fd = result['financialData'] as Map<String, dynamic>?;
      if (fd == null) { return null; }

      final meanRaw = (fd['targetMeanPrice'] as Map<String, dynamic>?)?['raw'];
      if (meanRaw == null) { return null; }

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
      if (result == null) { return null; }

      final meta = result['meta'] as Map<String, dynamic>?;
      final price = meta?['regularMarketPrice'];
      final currency = meta?['currency'] as String?;

      if (price == null || currency == null) { return null; }

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
      if (body == null) { return null; }

      final lines = body.trim().split('\n');
      if (lines.length < 2) { return null; }

      // CSV: Symbol,Date,Close
      final values = lines[1].split(',');
      if (values.length < 3) { return null; }

      final closeStr = values[2].trim();
      if (closeStr == 'N/D' || closeStr == 'N/A' || closeStr.isEmpty) {
        return null;
      }

      final close = Decimal.tryParse(closeStr);
      if (close == null || close == Decimal.zero) { return null; }

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
      if (result == null) { return null; }

      final quotes = result['indicators']?['quote'] as List?;
      final closes =
          (quotes?.firstOrNull as Map<String, dynamic>?)?['close'] as List?;
      // Use the last non-null close in the window (handles partial trading days).
      final close =
          closes?.reversed.firstWhere((c) => c != null, orElse: () => null);
      if (close != null) { return Decimal.parse(close.toString()); }

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
      if (body == null) { return null; }

      final lines = body.trim().split('\n');
      if (lines.length < 2) { return null; }

      // CSV: Date,Open,High,Low,Close,Volume
      final values = lines[1].split(',');
      if (values.length < 5) { return null; }

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
      if (result == null) { return []; }

      final events = result['events'] as Map<String, dynamic>?;
      final dividendsMap = events?['dividends'] as Map<String, dynamic>?;
      if (dividendsMap == null || dividendsMap.isEmpty) { return []; }

      final fetched = <FetchedDividend>[];
      for (final entry in dividendsMap.values) {
        if (entry is! Map<String, dynamic>) { continue; }
        final amount = entry['amount'];
        final timestamp = entry['date'];
        if (amount == null || timestamp == null) { continue; }

        final utc = DateTime.fromMillisecondsSinceEpoch(
            (timestamp as int) * 1000,
            isUtc: true);
        final amountDecimal = Decimal.tryParse(amount.toString());
        if (amountDecimal == null || amountDecimal <= Decimal.zero) { continue; }

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
    await _ensureSession();
    try {
      final response = await _yahooDio.get<Map<String, dynamic>>(
        '$_yahooQuoteSummaryUrl$symbol',
        queryParameters: _quoteSummaryParams({'modules': 'calendarEvents'}),
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final result =
          (response.data?['quoteSummary']?['result'] as List?)?.firstOrNull
              as Map<String, dynamic>?;
      if (result == null) { return null; }

      final calEvents = result['calendarEvents'] as Map<String, dynamic>?;
      final divDateRaw =
          (calEvents?['dividendDate'] as Map<String, dynamic>?)?['raw'];
      if (divDateRaw == null) { return null; }

      final utc = DateTime.fromMillisecondsSinceEpoch(
          (divDateRaw as int) * 1000,
          isUtc: true);
      final divDate = DateTime(utc.year, utc.month, utc.day);

      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      if (!divDate.isAfter(todayDate)) { return null; }

      // Use the most recent paid dividend amount as estimate for expected
      if (recentPaid.isEmpty) { return null; }
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

  /// Extracts the value of an HTML hidden input field by [name].
  /// Handles any attribute ordering within the <input> tag.
  String? _extractHidden(String html, String name) {
    // Non-raw strings: \\ → \ in the regex, \' → ' in the Dart string literal.
    // Match the full <input> tag containing name="<name>" in any attribute order.
    final tagPattern = RegExp(
      '<input\\b[^>]*\\bname=["\']${RegExp.escape(name)}["\'][^>]*>',
      caseSensitive: false,
      dotAll: true,
    );
    final tagMatch = tagPattern.firstMatch(html);
    if (tagMatch == null) { return null; }
    final valuePattern = RegExp('\\bvalue=["\']([^"\']*)["\']');
    return valuePattern.firstMatch(tagMatch.group(0)!)?.group(1);
  }
}
