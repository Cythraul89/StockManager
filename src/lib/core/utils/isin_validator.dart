// ISO 6166 ISIN validation using the Luhn-based check digit algorithm.
class IsinValidator {
  static final _isinRegex = RegExp(r'^[A-Z]{2}[A-Z0-9]{9}[0-9]$');

  static bool isValid(String isin) {
    if (!_isinRegex.hasMatch(isin)) return false;
    return _checkDigitValid(isin);
  }

  static bool _checkDigitValid(String isin) {
    // Convert letters to digits (A=10, B=11, … Z=35), then run Luhn mod-10.
    final digits = isin.split('').expand((c) {
      final code = c.codeUnitAt(0);
      if (code >= 48 && code <= 57) return [code - 48]; // 0–9
      return [code - 55]; // A=10 … Z=35; may be two digits
    }).expand((n) => n >= 10 ? [n ~/ 10, n % 10] : [n]).toList();

    int sum = 0;
    bool doubleIt = false;
    for (int i = digits.length - 1; i >= 0; i--) {
      int d = digits[i];
      if (doubleIt) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
      doubleIt = !doubleIt;
    }
    return sum % 10 == 0;
  }

  static String? errorMessage(String isin) {
    if (isin.isEmpty) return 'ISIN is required';
    if (isin.length != 12) return 'ISIN must be exactly 12 characters';
    if (!RegExp(r'^[A-Z]{2}').hasMatch(isin)) {
      return 'ISIN must start with a 2-letter country code';
    }
    if (!_isinRegex.hasMatch(isin)) return 'Invalid ISIN format';
    if (!_checkDigitValid(isin)) return 'Invalid ISIN check digit';
    return null;
  }
}
