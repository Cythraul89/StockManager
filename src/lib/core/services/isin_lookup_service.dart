import 'package:dio/dio.dart';

class IsinLookupResult {
  const IsinLookupResult({
    required this.symbol,
    required this.name,
    required this.exchange,
    required this.currency,
  });

  final String symbol;
  final String name;
  final String exchange;
  final String currency;
}

class IsinLookupService {
  IsinLookupService(this._dio);

  final Dio _dio;

  static const _openFigiUrl = 'https://api.openfigi.com/v3/mapping';

  Future<IsinLookupResult?> lookup(String isin) async {
    try {
      final response = await _dio.post<List>(
        _openFigiUrl,
        data: [
          {'idType': 'ID_ISIN', 'idValue': isin},
        ],
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final results = response.data;
      if (results == null || results.isEmpty) return null;

      final first = results.first as Map<String, dynamic>;
      final dataList = first['data'] as List?;
      if (dataList == null || dataList.isEmpty) return null;

      final item = dataList.first as Map<String, dynamic>;
      return IsinLookupResult(
        symbol: (item['ticker'] as String?) ?? '',
        name: (item['name'] as String?) ?? '',
        exchange: (item['exchCode'] as String?) ?? '',
        currency: (item['currency'] as String?) ?? '',
      );
    } on DioException {
      return null;
    }
  }
}
