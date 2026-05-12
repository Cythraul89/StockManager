import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';

import '../models/price_quote.dart';

class MarketDataService {
  MarketDataService(this._dio);

  final Dio _dio;

  static const _yahooBaseUrl = 'https://query1.finance.yahoo.com/v8/finance/chart/';

  Future<PriceQuote?> fetchQuote(String symbol, String stockId) async {
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
      final result = (chart?['result'] as List?)?.firstOrNull as Map<String, dynamic>?;
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

  // Fetch multiple quotes in parallel (up to 10 at a time to avoid rate limits).
  Future<Map<String, PriceQuote>> fetchQuotes(
    Map<String, String> symbolByStockId,
  ) async {
    final results = <String, PriceQuote>{};
    final entries = symbolByStockId.entries.toList();

    for (var i = 0; i < entries.length; i += 10) {
      final batch = entries.skip(i).take(10);
      final futures = batch.map((e) => fetchQuote(e.value, e.key));
      final quotes = await Future.wait(futures);
      for (final q in quotes) {
        if (q != null) results[q.stockId] = q;
      }
    }
    return results;
  }
}
