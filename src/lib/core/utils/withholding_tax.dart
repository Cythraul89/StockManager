import 'package:decimal/decimal.dart';

// Returns the standard source-country withholding tax rate on dividends
// based on the ISO 3166-1 alpha-2 country code embedded in the ISIN.
//
// Rates reflect common treaty (DBA) rates for portfolio investors.
// Pre-filled values are estimates — users should verify against their
// broker's tax documents and adjust accordingly.
Decimal withholdingTaxRate(String isin) {
  if (isin.length < 2) return Decimal.zero;
  final country = isin.substring(0, 2).toUpperCase();
  return switch (country) {
    // No source withholding
    'DE' || 'GB' || 'IE' || 'SG' || 'HK' || 'NZ' => Decimal.zero,
    // Switzerland: 35 % gross (20 % refundable under DBA CH–DE, but full
    // amount is typically deducted at source and reclaimed separately)
    'CH' => Decimal.parse('0.35'),
    // France: 12.8 % under DBA FR–DE
    'FR' => Decimal.parse('0.128'),
    // USA and most other common DBA countries: 15 %
    'US' || 'AT' || 'BE' || 'LU' || 'NL' || 'SE' || 'NO' || 'DK' ||
    'FI' || 'ES' || 'IT' || 'CA' || 'AU' || 'JP' || 'KR' || 'TW' ||
    'IN' || 'CN' || 'PT' || 'PL' || 'CZ' || 'HU' =>
      Decimal.parse('0.15'),
    _ => Decimal.zero,
  };
}
