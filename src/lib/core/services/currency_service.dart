import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';

import '../models/exchange_rate.dart';

class CurrencyService {
  CurrencyService(this._dio);

  final Dio _dio;

  // Open Exchange Rates free tier — base currency is always USD.
  static const _oxrBaseUrl = 'https://openexchangerates.org/api/latest.json';
  // App ID is optional for basic access but required for higher rate limits.
  static const _appId = '';

  Future<Map<String, ExchangeRate>> fetchRates(String baseCurrency) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _oxrBaseUrl,
        queryParameters: {
          if (_appId.isNotEmpty) 'app_id': _appId,
          'base': 'USD', // free tier only supports USD base
        },
        options: Options(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final rates = response.data?['rates'] as Map<String, dynamic>?;
      if (rates == null) return {};

      final now = DateTime.now();
      final result = <String, ExchangeRate>{};

      // Convert all rates to the user's preferred base currency.
      final baseRate = _parseRate(rates[baseCurrency]);
      if (baseRate == null || baseRate == Decimal.zero) return {};

      for (final entry in rates.entries) {
        final targetRate = _parseRate(entry.value);
        if (targetRate == null) continue;
        final rate = (targetRate / baseRate.toRational())
            .toDecimal(scaleOnInfinitePrecision: 10);
        result[entry.key] = ExchangeRate(
          base: baseCurrency,
          target: entry.key,
          rate: rate,
          fetchedAt: now,
          isManualOverride: false,
        );
      }
      return result;
    } on DioException {
      return {};
    }
  }

  static Decimal? _parseRate(dynamic value) {
    if (value == null) return null;
    try {
      return Decimal.parse(value.toString());
    } catch (_) {
      return null;
    }
  }
}
