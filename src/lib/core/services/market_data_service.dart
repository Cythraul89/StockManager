import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:intl/intl.dart';
import 'package:xml/xml.dart';

import '../models/analyst_data.dart';
import '../models/chart_range.dart';
import '../models/fetched_dividend.dart';
import '../models/news_article.dart';
import '../models/price_point.dart';
import '../models/price_quote.dart';
import '../utils/decimal_math.dart';

class MarketDataService {
  MarketDataService(this._dio) {
    // Dedicated Dio instance for authenticated Yahoo Finance requests.
    // followRedirects is left at the default (true) for normal requests;
    // _ensureSession overrides it per-request to collect Set-Cookie headers
    // from every hop in the GDPR consent redirect chain.
    _yahooDio = Dio(BaseOptions(
      headers: {
        'User-Agent': _userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
      },
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  final Dio _dio;
  late final Dio _yahooDio;

  static const _yahooBaseUrl =
      'https://query1.finance.yahoo.com/v8/finance/chart/';
  static const _yahooQuoteSummaryUrl =
      'https://query2.finance.yahoo.com/v10/finance/quoteSummary/';
  static const _stooqBaseUrl = 'https://stooq.com/q/l/';
  static const _stooqHistUrl = 'https://stooq.com/q/d/l/';

  static const _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0';

  // Crumb is required as a query param on quoteSummary calls. Cached 55 min.
  String? _crumb;
  String? _sessionCookie; // finance.yahoo.com cookies sent explicitly with quoteSummary
  DateTime? _sessionInitAt;
  // Prevents concurrent callers from each running the full GDPR flow in parallel.
  Completer<void>? _sessionInit;

  bool _isSessionValid() =>
      _crumb != null &&
      _sessionInitAt != null &&
      DateTime.now().difference(_sessionInitAt!).inMinutes < 55;

  /// Ensures a valid Yahoo Finance session (crumb + session cookies).
  /// Concurrent callers wait on the same in-flight init rather than each
  /// running the GDPR redirect chain simultaneously.
  Future<void> _ensureSession() async {
    if (_isSessionValid()) return;
    if (_sessionInit != null) return _sessionInit!.future;

    final completer = Completer<void>();
    _sessionInit = completer;
    try {
      await _doInitSession();
      completer.complete();
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _sessionInit = null;
    }
  }

  /// Performs the actual Yahoo Finance GDPR consent flow + crumb fetch.
  /// Errors are swallowed and logged; callers proceed and will fail gracefully
  /// on the subsequent API call (where 401/403 triggers session invalidation).
  Future<void> _doInitSession() async {
    try {
      // name→value map built from every Set-Cookie header we encounter.
      final cookieMap = <String, String>{};
      void gather(Response<dynamic> response) {
        for (final sc in response.headers.map['set-cookie'] ?? <String>[]) {
          final nv = sc.split(';').first.trim();
          final eq = nv.indexOf('=');
          if (eq > 0) {
            cookieMap[nv.substring(0, eq).trim()] =
                nv.substring(eq + 1).trim();
          }
        }
      }

      // ── Step 1: reach Yahoo Finance, following redirects manually ─────────
      // EU users are redirected to consent.yahoo.com.  We use
      // followRedirects: false at every hop so Set-Cookie headers from
      // intermediate 302 responses are visible and captured.
      var nextUrl = 'https://finance.yahoo.com/';
      String pageBody = '';
      for (var hop = 0; hop < 8 && nextUrl.isNotEmpty; hop++) {
        final resp = await _yahooDio.get<String>(
          nextUrl,
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (s) => s != null && s < 400,
          ),
        );
        gather(resp);
        final status = resp.statusCode ?? 0;
        final location = resp.headers['location']?.first;
        debugPrint('MarketDataService: GET $nextUrl → $status');
        if (status >= 300 && location != null) {
          nextUrl = location;
        } else {
          pageBody = resp.data ?? '';
          nextUrl = '';
        }
      }
      debugPrint('MarketDataService: landing page '
          'has_csrfToken=${pageBody.contains('csrfToken')} '
          'cookies_so_far=${cookieMap.length}');

      // ── Step 2: GDPR consent flow ─────────────────────────────────────────
      if (pageBody.contains('csrfToken')) {
        final csrfToken = _extractHidden(pageBody, 'csrfToken');
        final sessionId = _extractHidden(pageBody, 'sessionId');
        final originalDoneUrl = _extractHidden(pageBody, 'originalDoneUrl');
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
          gather(consentResp);
          debugPrint('MarketDataService: consent POST '
              'status=${consentResp.statusCode}');

          // Follow the post-consent redirect chain, gathering cookies at
          // each hop (Yahoo typically redirects back to finance.yahoo.com).
          var postConsentUrl = consentResp.headers['location']?.first;
          for (var hop = 0; postConsentUrl != null && hop < 5; hop++) {
            final resp = await _yahooDio.get<String>(
              postConsentUrl,
              options: Options(
                responseType: ResponseType.plain,
                followRedirects: false,
                validateStatus: (s) => s != null && s < 400,
              ),
            );
            gather(resp);
            final status = resp.statusCode ?? 0;
            debugPrint(
                'MarketDataService: post-consent hop $hop → $status');
            postConsentUrl =
                status >= 300 ? resp.headers['location']?.first : null;
          }
        }
      }

      _sessionCookie = cookieMap.isEmpty
          ? null
          : cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
      debugPrint('MarketDataService: gathered ${cookieMap.length} session '
          'cookies: ${cookieMap.keys.toList()}');

      // ── Step 3: fetch crumb ───────────────────────────────────────────────
      final crumbResp = await _yahooDio.get<String>(
        'https://query2.finance.yahoo.com/v1/test/getcrumb',
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            if (_sessionCookie != null) 'Cookie': _sessionCookie!,
            'Accept': 'application/json, text/plain, */*',
            'Referer': 'https://finance.yahoo.com/',
          },
        ),
      );
      // Capture any additional cookies the crumb endpoint sets, then rebuild
      // _sessionCookie so subsequent API calls carry the full cookie set.
      gather(crumbResp);
      _sessionCookie = cookieMap.isEmpty
          ? null
          : cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');

      final crumb = crumbResp.data?.trim();
      debugPrint('MarketDataService: crumb status=${crumbResp.statusCode} '
          'len=${crumb?.length} crumb="$crumb"');
      if (crumb != null && crumb.isNotEmpty && !crumb.startsWith('{')) {
        _crumb = crumb;
        _sessionInitAt = DateTime.now();
        debugPrint('MarketDataService: session established');
      }
    } catch (e) {
      debugPrint('MarketDataService: Yahoo session init failed: $e');
    }
  }

  Map<String, dynamic> _quoteSummaryParams(Map<String, dynamic> base) => {
        ...base,
        if (_crumb != null) 'crumb': _crumb!,
        'corsDomain': 'finance.yahoo.com',
        'lang': 'en-US',
        'region': 'US',
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

  /// Fetches analyst consensus, 52-week range, valuation, and recommendation
  /// breakdown from Yahoo Finance quoteSummary in a single request.
  Future<AnalystData?> fetchAnalystData(String symbol) async {
    await _ensureSession();
    try {
      final response = await _withYahooRetry(() => _yahooDio.get<Map<String, dynamic>>(
        '$_yahooQuoteSummaryUrl$symbol',
        queryParameters: _quoteSummaryParams({
          'modules':
              'financialData,summaryDetail,defaultKeyStatistics,recommendationTrend',
        }),
        options: Options(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            if (_sessionCookie != null) 'Cookie': _sessionCookie!,
            'Accept': 'application/json, text/plain, */*',
            'Referer': 'https://finance.yahoo.com/quote/$symbol/',
          },
        ),
      ));

      debugPrint('MarketDataService: quoteSummary[$symbol] '
          'status=${response.statusCode}');
      final result =
          (response.data?['quoteSummary']?['result'] as List?)?.firstOrNull
              as Map<String, dynamic>?;
      if (result == null) {
        debugPrint('MarketDataService: quoteSummary result=null, '
            'error=${response.data?['quoteSummary']?['error']}');
        return null;
      }

      // Helper: extract the 'raw' numeric value from a Yahoo formatted object.
      Decimal? raw(Map<String, dynamic>? section, String key) {
        final v = (section?[key] as Map<String, dynamic>?)?['raw'];
        return v != null ? Decimal.tryParse(v.toString()) : null;
      }

      // ── financialData ─────────────────────────────────────────────────────
      final fd = result['financialData'] as Map<String, dynamic>?;
      final meanPrice = raw(fd, 'targetMeanPrice');
      if (meanPrice == null) { return null; }
      final recKey = fd?['recommendationKey'] as String?;
      final numRaw = (fd?['numberOfAnalystOpinions']
              as Map<String, dynamic>?)?['raw'];
      final currency = fd?['financialCurrency'] as String?;
      debugPrint('MarketDataService: quoteSummary[$symbol] '
          'financialCurrency=$currency');

      // ── summaryDetail ─────────────────────────────────────────────────────
      final sd = result['summaryDetail'] as Map<String, dynamic>?;

      // ── defaultKeyStatistics ──────────────────────────────────────────────
      final dks = result['defaultKeyStatistics'] as Map<String, dynamic>?;

      // ── recommendationTrend — use the most recent (first) period ──────────
      final trends = (result['recommendationTrend']?['trend'] as List?)
          ?.cast<Map<String, dynamic>>();
      final trend = trends?.firstOrNull;

      return AnalystData(
        targetMeanPrice: meanPrice,
        targetLowPrice: raw(fd, 'targetLowPrice'),
        targetHighPrice: raw(fd, 'targetHighPrice'),
        recommendationKey: recKey?.isNotEmpty == true ? recKey : null,
        numberOfAnalysts: numRaw is int ? numRaw : null,
        financialCurrency: currency,
        // Consensus breakdown
        strongBuyCount: trend?['strongBuy'] as int?,
        buyCount: trend?['buy'] as int?,
        holdCount: trend?['hold'] as int?,
        sellCount: trend?['sell'] as int?,
        strongSellCount: trend?['strongSell'] as int?,
        // 52-week range
        fiftyTwoWeekLow: raw(sd, 'fiftyTwoWeekLow'),
        fiftyTwoWeekHigh: raw(sd, 'fiftyTwoWeekHigh'),
        // Valuation
        trailingPE: raw(sd, 'trailingPE'),
        forwardPE: raw(sd, 'forwardPE'),
        trailingEps: raw(dks, 'trailingEps'),
        // 52-week return as a fraction (e.g. 0.157 = +15.7%)
        yearChangePct: raw(dks, '52WeekChange'),
        // Dividends — fiveYearAvgDividendYield is already in % (e.g. 3.5 = 3.5%)
        fiveYearAvgDividendYield: raw(sd, 'fiveYearAvgDividendYield'),
        trailingAnnualDividendRate: raw(sd, 'trailingAnnualDividendRate'),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Stale session — force re-auth on the next call rather than waiting
      // out the 55-minute TTL with a known-bad crumb.
      if (status == 401 || status == 403) _crumb = null;
      final body = e.response?.data?.toString() ?? '';
      debugPrint('MarketDataService: quoteSummary[$symbol] error '
          'status=$status '
          'body=${body.length > 400 ? body.substring(0, 400) : body}');
      return null;
    } catch (e) {
      debugPrint('MarketDataService: analyst data fetch failed for $symbol: $e');
      return null;
    }
  }

  /// Fetches analyst data from Finnhub using three parallel requests:
  /// price-target, recommendation trend, and basic financials.
  Future<AnalystData?> fetchAnalystDataFromFinnhub(
      String symbol, String apiKey) async {
    const base = 'https://finnhub.io/api/v1';
    try {
      final responses = await Future.wait([
        _dio.get<dynamic>('$base/stock/price-target',
            queryParameters: {'symbol': symbol, 'token': apiKey}),
        _dio.get<dynamic>('$base/stock/recommendation',
            queryParameters: {'symbol': symbol, 'token': apiKey}),
        _dio.get<dynamic>('$base/stock/metric',
            queryParameters: {
              'symbol': symbol,
              'metric': 'all',
              'token': apiKey,
            }),
      ]);

      // ── Price target ────────────────────────────────────────────────────
      final pt = responses[0].data as Map<String, dynamic>?;
      final targetMean = _fhDecimal(pt, 'targetMean');
      if (targetMean == null || targetMean.isZero) return null;

      // ── Recommendation trend (most-recent period first) ─────────────────
      final recList = (responses[1].data as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .toList();
      final rec = recList?.firstOrNull;
      final sb = rec?['strongBuy']  as int? ?? 0;
      final b  = rec?['buy']        as int? ?? 0;
      final h  = rec?['hold']       as int? ?? 0;
      final s  = rec?['sell']       as int? ?? 0;
      final ss = rec?['strongSell'] as int? ?? 0;
      final total = sb + b + h + s + ss;

      // ── Basic financials ────────────────────────────────────────────────
      final metricsMap = responses[2].data as Map<String, dynamic>?;
      final m = metricsMap?['metric'] as Map<String, dynamic>?;

      // Finnhub 52-week return is in % (e.g. 15.7); convert to fraction.
      final raw52w = _fhDecimal(m, '52WeekPriceReturnDaily');
      final yearChangePct = raw52w != null
          ? (raw52w.toRational() / Decimal.fromInt(100).toRational())
              .toDecimal(scaleOnInfinitePrecision: 4)
          : null;

      return AnalystData(
        targetMeanPrice: targetMean,
        targetLowPrice:  _fhDecimal(pt, 'targetLow'),
        targetHighPrice: _fhDecimal(pt, 'targetHigh'),
        recommendationKey:
            total > 0 ? _fhRecKey(sb, b, h, s, ss, total) : null,
        numberOfAnalysts: total > 0 ? total : null,
        financialCurrency: null,
        strongBuyCount:  sb > 0 ? sb : null,
        buyCount:        b  > 0 ? b  : null,
        holdCount:       h  > 0 ? h  : null,
        sellCount:       s  > 0 ? s  : null,
        strongSellCount: ss > 0 ? ss : null,
        fiftyTwoWeekLow:  _fhDecimal(m, '52WeekLow'),
        fiftyTwoWeekHigh: _fhDecimal(m, '52WeekHigh'),
        trailingPE: _fhDecimal(m, 'peExclExtraTTM') ??
            _fhDecimal(m, 'peNormalizedAnnual'),
        forwardPE:  _fhDecimal(m, 'forwardPE'),
        trailingEps: _fhDecimal(m, 'epsBasicExclExtraAnnual') ??
            _fhDecimal(m, 'epsNormalizedAnnual'),
        yearChangePct: yearChangePct,
        fiveYearAvgDividendYield:  _fhDecimal(m, 'dividendYield5Y'),
        trailingAnnualDividendRate: _fhDecimal(m, 'dividendPerShareAnnual'),
      );
    } catch (e) {
      debugPrint(
          'MarketDataService: Finnhub analyst fetch failed for $symbol: $e');
      return null;
    }
  }

  Future<AnalystData?> fetchAnalystDataFinnhubWithFallback(
      String symbol, String apiKey) async {
    final results = await Future.wait([
      fetchAnalystDataFromFinnhub(symbol, apiKey),
      fetchAnalystData(symbol),
    ]);
    final fh = results[0];
    final yh = results[1];
    if (fh == null) return yh;
    if (yh == null) return fh;
    return AnalystData(
      targetMeanPrice: fh.targetMeanPrice,
      targetLowPrice: fh.targetLowPrice ?? yh.targetLowPrice,
      targetHighPrice: fh.targetHighPrice ?? yh.targetHighPrice,
      recommendationKey: fh.recommendationKey ?? yh.recommendationKey,
      numberOfAnalysts: fh.numberOfAnalysts ?? yh.numberOfAnalysts,
      financialCurrency: fh.financialCurrency ?? yh.financialCurrency,
      strongBuyCount: fh.strongBuyCount ?? yh.strongBuyCount,
      buyCount: fh.buyCount ?? yh.buyCount,
      holdCount: fh.holdCount ?? yh.holdCount,
      sellCount: fh.sellCount ?? yh.sellCount,
      strongSellCount: fh.strongSellCount ?? yh.strongSellCount,
      fiftyTwoWeekLow: fh.fiftyTwoWeekLow ?? yh.fiftyTwoWeekLow,
      fiftyTwoWeekHigh: fh.fiftyTwoWeekHigh ?? yh.fiftyTwoWeekHigh,
      trailingPE: fh.trailingPE ?? yh.trailingPE,
      forwardPE: fh.forwardPE ?? yh.forwardPE,
      trailingEps: fh.trailingEps ?? yh.trailingEps,
      yearChangePct: fh.yearChangePct ?? yh.yearChangePct,
      fiveYearAvgDividendYield:
          fh.fiveYearAvgDividendYield ?? yh.fiveYearAvgDividendYield,
      trailingAnnualDividendRate:
          fh.trailingAnnualDividendRate ?? yh.trailingAnnualDividendRate,
    );
  }

  static Decimal? _fhDecimal(Map<String, dynamic>? map, String key) {
    final v = map?[key];
    if (v == null) return null;
    return Decimal.tryParse(v.toString());
  }

  // Derives a Yahoo-compatible recommendationKey from Finnhub counts using a
  // weighted score: strongBuy=+2, buy=+1, hold=0, sell=−1, strongSell=−2.
  static String _fhRecKey(int sb, int b, int h, int s, int ss, int total) {
    final score = (sb * 2 + b - s - ss * 2) / total;
    if (score > 1.2)  return 'strong_buy';
    if (score > 0.4)  return 'buy';
    if (score > -0.4) return 'hold';
    if (score > -1.2) return 'sell';
    return 'strong_sell';
  }


  /// Returns an empty list when the symbol is unknown or the API is unreachable.
  Future<List<PricePoint>> fetchPriceHistory(
      String symbol, ChartRange range) async {
    try {
      final response =
          await _withYahooRetry(() => _dio.get<Map<String, dynamic>>(
                '$_yahooBaseUrl$symbol',
                queryParameters: {
                  'interval': range.yahooInterval,
                  'range': range.yahooRange,
                },
                options: Options(
                  sendTimeout: const Duration(seconds: 15),
                  receiveTimeout: const Duration(seconds: 15),
                ),
              ));

      final chart = response.data?['chart'] as Map<String, dynamic>?;
      final result =
          (chart?['result'] as List?)?.firstOrNull as Map<String, dynamic>?;
      if (result == null) return [];

      final meta = result['meta'] as Map<String, dynamic>?;
      final rawCurrency = (meta?['currency'] as String?) ?? '';
      if (rawCurrency.isEmpty) return [];

      final timestamps = (result['timestamp'] as List?)?.cast<int>();
      final quotes = result['indicators']?['quote'] as List?;
      final closes =
          (quotes?.firstOrNull as Map<String, dynamic>?)?['close'] as List?;
      if (timestamps == null || closes == null) return [];

      final points = <PricePoint>[];
      for (var i = 0; i < timestamps.length && i < closes.length; i++) {
        final close = closes[i];
        if (close == null) continue;
        final rawPrice = Decimal.tryParse(close.toString());
        if (rawPrice == null || rawPrice <= Decimal.zero) continue;
        final (price, currency) = _normalizeCurrency(rawPrice, rawCurrency);
        points.add(PricePoint(
          date: DateTime.fromMillisecondsSinceEpoch(timestamps[i] * 1000),
          price: price,
          currency: currency,
        ));
      }
      return points;
    } on DioException {
      return [];
    } catch (e) {
      debugPrint(
          'MarketDataService: price history fetch failed for $symbol: $e');
      return [];
    }
  }

  /// Returns up to 10 recent news articles for [symbol].
  /// Uses Finnhub company-news when [finnhubApiKey] is provided; falls back to
  /// Yahoo Finance search otherwise.
  Future<List<NewsArticle>> fetchNews(String symbol,
      {String? finnhubApiKey}) async {
    if (finnhubApiKey != null && finnhubApiKey.isNotEmpty) {
      try {
        return await _fetchNewsFromFinnhub(symbol, finnhubApiKey);
      } catch (e) {
        debugPrint('MarketDataService: Finnhub news failed for $symbol: $e');
      }
    }
    try {
      return await _fetchNewsFromYahoo(symbol);
    } catch (e) {
      debugPrint('MarketDataService: Yahoo news failed for $symbol: $e');
      return [];
    }
  }

  Future<List<NewsArticle>> _fetchNewsFromFinnhub(
      String symbol, String apiKey) async {
    const base = 'https://finnhub.io/api/v1';
    final fmt = DateFormat('yyyy-MM-dd');
    final now = DateTime.now();
    final response = await _dio.get<dynamic>(
      '$base/company-news',
      queryParameters: {
        'symbol': symbol,
        'from': fmt.format(now.subtract(const Duration(days: 7))),
        'to': fmt.format(now),
        'token': apiKey,
      },
    );
    final list = (response.data as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>() ??
        [];
    return list.take(10).map((item) {
      final ts = item['datetime'] as int? ?? 0;
      return NewsArticle(
        headline: item['headline'] as String? ?? '',
        url: item['url'] as String? ?? '',
        source: item['source'] as String? ?? '',
        publishedAt: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
        summary: item['summary'] as String?,
      );
    }).where((a) => a.headline.isNotEmpty && a.url.isNotEmpty).toList();
  }

  Future<List<NewsArticle>> _fetchNewsFromYahoo(String symbol) async {
    // Use the Yahoo Finance RSS feed — it filters strictly by symbol, unlike
    // the search endpoint which returns general news for any matching query.
    final response = await _dio.get<String>(
      'https://feeds.finance.yahoo.com/rss/2.0/headline',
      queryParameters: {'s': symbol, 'region': 'US', 'lang': 'en-US'},
    );
    if (response.data == null || response.data!.isEmpty) return [];

    final document = XmlDocument.parse(response.data!);
    final items = document.findAllElements('item');

    return items.take(10).map((item) {
      final title = item.findElements('title').firstOrNull?.innerText ?? '';
      // In RSS 2.0 <link> is a text sibling, not a child element — use the
      // next sibling text node trick, but innerText on the element works for
      // feeds that wrap the URL in the element content.
      final link = item.findElements('link').firstOrNull?.innerText ??
          item.findElements('guid').firstOrNull?.innerText ??
          '';
      final pubDateStr =
          item.findElements('pubDate').firstOrNull?.innerText ?? '';
      final source = item.findElements('source').firstOrNull?.innerText ?? '';

      return NewsArticle(
        headline: title,
        url: link,
        source: source,
        publishedAt: _parseRssDate(pubDateStr),
      );
    }).where((a) => a.headline.isNotEmpty && a.url.isNotEmpty).toList();
  }

  // RFC 822 date format used in RSS feeds: "Mon, 19 May 2026 14:30:00 +0000"
  static final _rssFmt =
      DateFormat('EEE, dd MMM yyyy HH:mm:ss Z', 'en_US');

  static DateTime _parseRssDate(String s) {
    try {
      return _rssFmt.parse(s.trim(), true).toLocal();
    } catch (_) {
      return DateTime.now();
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

  // Backoff durations for HTTP 429 retries: 2 s, 4 s, 8 s.
  static const _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];

  /// Calls [fn] and retries with exponential backoff on HTTP 429 (rate limit).
  /// Every other [DioException] is re-thrown immediately so callers can handle
  /// it as they normally would.
  Future<T> _withYahooRetry<T>(Future<T> Function() fn) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await fn();
      } on DioException catch (e) {
        if (e.response?.statusCode == 429 && attempt < _retryDelays.length) {
          final delay = _retryDelays[attempt];
          debugPrint('MarketDataService: rate limited (429), '
              'retry ${attempt + 1} in ${delay.inSeconds}s');
          await Future.delayed(delay);
          continue;
        }
        rethrow;
      }
    }
  }

  /// Yahoo Finance quotes London-listed securities in pence ("GBp" / "GBX"),
  /// which is 1/100th of a pound.  Normalise to GBP so all downstream math
  /// (P&L, currency conversion) operates in the major currency unit.
  static (Decimal, String) _normalizeCurrency(Decimal price, String currency) {
    if (currency == 'GBp' || currency == 'GBX') {
      final gbp = (price.toRational() / Decimal.fromInt(100).toRational())
          .toDecimal(scaleOnInfinitePrecision: 6);
      return (gbp, 'GBP');
    }
    return (price, currency);
  }

  Future<PriceQuote?> _fetchFromYahoo(String symbol, String stockId) async {
    try {
      final response = await _withYahooRetry(() => _dio.get<Map<String, dynamic>>(
        '$_yahooBaseUrl$symbol',
        queryParameters: {'interval': '1d', 'range': '1d'},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      ));

      final chart = response.data?['chart'] as Map<String, dynamic>?;
      final result =
          (chart?['result'] as List?)?.firstOrNull as Map<String, dynamic>?;
      if (result == null) { return null; }

      final meta = result['meta'] as Map<String, dynamic>?;
      final price = meta?['regularMarketPrice'];
      final currency = meta?['currency'] as String?;

      if (price == null || currency == null) { return null; }

      final (normPrice, normCurrency) = _normalizeCurrency(
          Decimal.parse(price.toString()), currency);

      final changePct = meta?['regularMarketChangePercent'];
      return PriceQuote(
        stockId: stockId,
        price: normPrice,
        currency: normCurrency,
        fetchedAt: DateTime.now(),
        dayChangePct: changePct != null
            ? Decimal.tryParse(changePct.toString())
            : null,
      );
    } on DioException {
      return null;
    }
  }

  // Stooq does not return currency metadata, so [currency] is taken from the
  // stock record (already normalized, e.g. 'GBP').  Stooq uses different
  // symbol suffixes (.UK vs Yahoo's .L), so London-listed symbols typically
  // return null here rather than a pence-denominated price — the safe outcome.
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

      final response = await _withYahooRetry(() => _dio.get<Map<String, dynamic>>(
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
      ));

      final chart = response.data?['chart'] as Map<String, dynamic>?;
      final result =
          (chart?['result'] as List?)?.firstOrNull as Map<String, dynamic>?;
      if (result == null) { return null; }

      final rawCurrency = (result['meta']?['currency'] as String?) ?? '';
      final quotes = result['indicators']?['quote'] as List?;
      final closes =
          (quotes?.firstOrNull as Map<String, dynamic>?)?['close'] as List?;
      // Use the last non-null close in the window (handles partial trading days).
      final close =
          closes?.reversed.firstWhere((c) => c != null, orElse: () => null);
      if (close != null) {
        final (price, _) = _normalizeCurrency(
            Decimal.parse(close.toString()), rawCurrency);
        return price;
      }

      return null;
    } on DioException {
      return null;
    }
  }

  // Same caveat as _fetchFromStooq: no currency metadata returned.
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

      final rawCurrency = (result['meta']?['currency'] as String?) ?? '';
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
        var amountDecimal = Decimal.tryParse(amount.toString());
        if (amountDecimal == null || amountDecimal <= Decimal.zero) { continue; }

        final (normAmount, normCurrency) =
            _normalizeCurrency(amountDecimal, rawCurrency);
        fetched.add(FetchedDividend(
          date: DateTime(utc.year, utc.month, utc.day),
          amountPerShare: normAmount,
          currency: normCurrency,
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
      final response = await _withYahooRetry(() => _yahooDio.get<Map<String, dynamic>>(
        '$_yahooQuoteSummaryUrl$symbol',
        queryParameters: _quoteSummaryParams({'modules': 'calendarEvents'}),
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {
            if (_sessionCookie != null) 'Cookie': _sessionCookie!,
            'Accept': 'application/json, text/plain, */*',
            'Referer': 'https://finance.yahoo.com/quote/$symbol/',
          },
        ),
      ));

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
        currency: lastPaid.currency,
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
