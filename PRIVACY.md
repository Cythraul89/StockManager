# Privacy Policy — StockManager

Last updated: 2026-05-18

## Summary

StockManager stores all portfolio data locally on your device. No data is uploaded to any server operated by this application or its developers.

---

## Data stored on your device

All portfolio data (brokers, stocks, transactions, dividends, settings) is stored in a local SQLite database on your device. It never leaves your device unless you explicitly trigger a Nextcloud sync or an AI analysis request.

---

## Data sent to third-party services

When an internet connection is available, the app contacts the following external services:

| Service | Data sent | Purpose | When |
|---|---|---|---|
| Yahoo Finance (`finance.yahoo.com`) | Ticker symbol | Live price quotes, chart data | Automatically, when the app is open |
| OpenFIGI (`openfigi.com`) | ISIN | Resolving ticker, name, exchange, currency | When you add or research a stock |
| Open Exchange Rates (`openexchangerates.org`) | None | Currency exchange rates | Automatically, when the app is open |
| Finnhub (`finnhub.io`) | Ticker symbol | Analyst ratings and price targets | When you view a stock's analysis card (only if a Finnhub API key is configured) |
| Anthropic (`anthropic.com`) | Portfolio data (stocks, transactions, current valuations) | AI portfolio analysis | Only when you explicitly request an analysis and have configured an Anthropic API key |

No names, email addresses, passwords, device identifiers, or personally identifying information are transmitted to any of the services above.

---

## Nextcloud synchronisation

If you configure Nextcloud sync, the app uploads a backup file (ODS spreadsheet containing your portfolio data) to **your own** Nextcloud server using credentials you provide. This data goes directly to your server; it is not routed through or visible to the developers of StockManager.

---

## Analytics and tracking

StockManager contains no analytics, crash-reporting, advertising, or user-tracking SDKs. The developers receive no telemetry of any kind.

---

## Data retention and deletion

All data is stored on your device. Uninstalling the app removes all locally stored data. Any backups you have uploaded to your Nextcloud instance must be deleted there separately.

---

## Contact

For questions about this privacy policy, please open an issue at:  
<https://github.com/Cythraul89/StockManager/issues>
