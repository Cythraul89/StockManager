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
      final ticker = (item['ticker'] as String?) ?? '';
      final exchCode = (item['exchCode'] as String?) ?? '';
      final suffix = _yahooSuffix(exchCode);
      return IsinLookupResult(
        symbol: suffix.isEmpty ? ticker : '$ticker$suffix',
        name: (item['name'] as String?) ?? '',
        exchange: exchCode,
        currency: (item['currency'] as String?) ?? '',
      );
    } on DioException {
      return null;
    }
  }

  // Maps OpenFIGI exchCode (Bloomberg market code) to Yahoo Finance ticker suffix.
  // US exchanges need no suffix; all others append one.
  static String _yahooSuffix(String exchCode) => const {
        'GY': '.DE', // XETRA
        'GF': '.F',  // Frankfurt
        'LN': '.L',  // London
        'FP': '.PA', // Euronext Paris
        'NA': '.AS', // Amsterdam
        'BB': '.BR', // Brussels
        'SM': '.MC', // Madrid
        'IM': '.MI', // Milan
        'SW': '.SW', // SIX Swiss Exchange
        'AV': '.VI', // Vienna
        'DC': '.CO', // Copenhagen
        'SS': '.ST', // Stockholm
        'HB': '.HE', // Helsinki
        'NO': '.OL', // Oslo
        'JT': '.T',  // Tokyo
        'HK': '.HK', // Hong Kong
        'AT': '.AX', // Australia (ASX)
        'CT': '.TO', // Toronto
        'CF': '.V',  // TSX Venture
        'LS': '.LS', // Lisbon
        'PW': '.WA', // Warsaw
      }[exchCode] ??
      '';
}
