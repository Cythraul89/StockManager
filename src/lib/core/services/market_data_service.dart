import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/price_quote.dart';

class MarketDataService {
  MarketDataService(this._dio);

  final Dio _dio;

  static const _yahooBaseUrl =
      'https://query1.finance.yahoo.com/v8/finance/chart/';
  static const _stooqBaseUrl = 'https://stooq.com/q/l/';

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
        queryParameters: {'s': symbol, 'f': 'sd2c', 'e': 'csv'},
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
    } on DioException catch (e) {
      debugPrint('MarketDataService: Stooq fetch failed for $symbol: $e');
      return null;
    }
  }
}
