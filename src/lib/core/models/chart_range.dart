enum ChartRange {
  oneDay('1D', '1d', '5m'),
  oneWeek('1W', '5d', '1d'),
  oneMonth('1M', '1mo', '1d'),
  sixMonths('6M', '6mo', '1d'),
  oneYear('1Y', '1y', '1wk'),
  fiveYears('5Y', '5y', '1wk'),
  max('MAX', 'max', '1mo');

  const ChartRange(this.label, this.yahooRange, this.yahooInterval);

  final String label;
  // Parameters passed directly to the Yahoo Finance chart API.
  final String yahooRange;
  final String yahooInterval;
}
