enum AssetType {
  stock('Stock', 'stock'),
  etf('ETF', 'etf'),
  etc('ETC', 'etc'),
  fund('Fund', 'fund'),
  bond('Bond', 'bond'),
  warrant('Warrant', 'warrant'),
  other('Other', 'other');

  const AssetType(this.label, this.dbValue);

  final String label;
  final String dbValue;

  static AssetType fromDb(String? value) => switch (value?.toLowerCase()) {
        'etf' => etf,
        'etc' => etc,
        'fund' => fund,
        'bond' => bond,
        'warrant' => warrant,
        'other' => other,
        _ => stock,
      };

  // Derives the asset type from the raw OpenFIGI securityType string.
  // ETC is checked before the broader ETF/ETP patterns to avoid
  // misclassifying commodity products as equity ETFs.
  static AssetType fromSecurityType(String securityType) {
    final s = securityType.toLowerCase();

    if (s == 'etc' ||
        s.contains('exchange traded commodity') ||
        s.contains('commodity certificate')) {
      return etc;
    }
    // ETN (Exchange Traded Note) is debt-like — treat as bond.
    if (s == 'etn' || s.contains('exchange traded note')) {
      return bond;
    }
    if (s == 'etf' ||
        s == 'etp' ||
        s.contains('etf') ||
        s.contains('exchange traded fund') ||
        s.contains('exchange traded product')) {
      return etf;
    }
    if (s.contains('bond') ||
        s.contains('note') ||
        s.contains('debenture') ||
        s.contains('treasury') ||
        s.contains('gilt')) {
      return bond;
    }
    if (s.contains('fund') ||
        s.contains('sicav') ||
        s.contains('ucits') ||
        s.contains('mutual')) {
      return fund;
    }
    if (s.contains('warrant') || s.contains('right')) {
      return warrant;
    }
    if (s.contains('common') ||
        s.contains('ordinary') ||
        s.contains('share') ||
        s.contains('stock') ||
        s.contains('adr') ||
        s.contains('gdr') ||
        s.contains('preferred')) {
      return stock;
    }
    return other;
  }
}
