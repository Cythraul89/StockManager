import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/exchange_rate.dart';

class CurrencyService {
  CurrencyService(this._dio);

  final Dio _dio;

  // Frankfurter (api.frankfurter.app) — ECB data, free, no API key.
  // Returns rates relative to a chosen base currency.
  static const _baseUrl = 'https://api.frankfurter.app/latest';

  Future<Map<String, ExchangeRate>> fetchRates(String baseCurrency) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _baseUrl,
        queryParameters: {'from': baseCurrency},
        options: Options(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final rates = response.data?['rates'] as Map<String, dynamic>?;
      if (rates == null) return {};

      final now = DateTime.now();
      final result = <String, ExchangeRate>{};

      // Frankfurter returns "1 baseCurrency = X other" (otherPerBase).
      // We need rate = baseCurrencyPerOther = 1 / otherPerBase so that
      // ExchangeRate.convert(amount_in_other) = amount_in_other * rate
      // gives the correct amount in baseCurrency.
      for (final entry in rates.entries) {
        final otherPerBase = _parseRate(entry.value);
        if (otherPerBase == null || otherPerBase == Decimal.zero) continue;
        final rate = (Decimal.one.toRational() / otherPerBase.toRational())
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
    } on DioException catch (e) {
      debugPrint('CurrencyService: fetchRates failed: $e');
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
