import 'package:dio/dio.dart';

class IsinLookupResult {
  const IsinLookupResult({
    required this.symbol,
    required this.name,
    required this.exchange,
    required this.exchangeName,
    required this.currency,
    required this.securityType,
  });

  final String symbol;
  final String name;
  final String exchange;
  final String exchangeName;
  final String currency;
  final String securityType;
}

class IsinLookupService {
  IsinLookupService(this._dio);

  final Dio _dio;

  static const _openFigiUrl = 'https://api.openfigi.com/v3/mapping';

  // Returns all distinct exchange listings for the given ISIN, filtered to
  // equity types where possible. Returns null on network error.
  Future<List<IsinLookupResult>?> lookup(String isin) async {
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

      final raw = dataList.whereType<Map<String, dynamic>>().toList();

      // Prefer equity-type entries; fall back to all entries if none found.
      var equities = raw.where((e) {
        final st = ((e['securityType'] as String?) ?? '').toLowerCase();
        return st.contains('common') ||
            st.contains('ordinary') ||
            st.contains('share');
      }).toList();
      final candidates = equities.isNotEmpty ? equities : raw;

      // Deduplicate by (exchCode, ticker) keeping first occurrence.
      final seen = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (final item in candidates) {
        final key = '${item["exchCode"]}:${item["ticker"]}';
        if (seen.add(key)) deduped.add(item);
      }

      return deduped.map((item) {
        final ticker = (item['ticker'] as String?) ?? '';
        final exchCode = (item['exchCode'] as String?) ?? '';
        final exchangeSuffix = _yahooSuffix(exchCode);
        final suffix = exchangeSuffix.isNotEmpty
            ? exchangeSuffix
            : _suffixFromIsin(isin);
        return IsinLookupResult(
          symbol: suffix.isEmpty ? ticker : '$ticker$suffix',
          name: (item['name'] as String?) ?? '',
          exchange: exchCode,
          exchangeName: _exchangeName(exchCode),
          currency: (item['currency'] as String?) ?? '',
          securityType: (item['securityType'] as String?) ?? '',
        );
      }).toList();
    } on DioException {
      return null;
    }
  }

  // Maps OpenFIGI exchCode to Yahoo Finance ticker suffix.
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
        'HK': '.HK', // HKEX
        'AT': '.AX', // ASX
        'CT': '.TO', // Toronto
        'CF': '.V',  // TSX Venture
        'LS': '.LS', // Lisbon
        'PW': '.WA', // Warsaw
      }[exchCode] ??
      '';

  // Falls back to Yahoo Finance suffix derived from the ISIN country prefix.
  static String _suffixFromIsin(String isin) {
    if (isin.length < 2) return '';
    return const {
      'DE': '.DE', 'AT': '.VI', 'GB': '.L',  'FR': '.PA',
      'NL': '.AS', 'BE': '.BR', 'ES': '.MC', 'IT': '.MI',
      'CH': '.SW', 'DK': '.CO', 'SE': '.ST', 'FI': '.HE',
      'NO': '.OL', 'PT': '.LS', 'PL': '.WA', 'JP': '.T',
      'HK': '.HK', 'AU': '.AX', 'CA': '.TO',
    }[isin.substring(0, 2)] ?? '';
  }

  // Human-readable exchange name for display.
  static String _exchangeName(String exchCode) => const {
        'GY': 'XETRA',
        'GF': 'Frankfurt',
        'LN': 'London Stock Exchange',
        'FP': 'Euronext Paris',
        'NA': 'Euronext Amsterdam',
        'BB': 'Euronext Brussels',
        'SM': 'Bolsa de Madrid',
        'IM': 'Borsa Italiana',
        'SW': 'SIX Swiss Exchange',
        'AV': 'Vienna Stock Exchange',
        'DC': 'Nasdaq Copenhagen',
        'SS': 'Nasdaq Stockholm',
        'HB': 'Nasdaq Helsinki',
        'NO': 'Oslo Stock Exchange',
        'JT': 'Tokyo Stock Exchange',
        'HK': 'HKEX',
        'AT': 'ASX',
        'CT': 'Toronto Stock Exchange',
        'CF': 'TSX Venture',
        'LS': 'Euronext Lisbon',
        'PW': 'Warsaw Stock Exchange',
        'UN': 'NYSE',
        'UW': 'NASDAQ',
        'UA': 'NYSE American',
        'UP': 'OTC Markets',
        'US': 'NYSE',
      }[exchCode] ??
      exchCode;
}
