# StockManager — Architecture

## 1. Technology Stack

| Concern | Library / Tool | Rationale |
|---|---|---|
| Framework | Flutter (Dart) | Single codebase for Android + macOS + Windows + Ubuntu |
| State management | Riverpod | Async-first, composable providers, easy to unit-test |
| Local database | Drift (SQLite) | Type-safe, reactive streams, first-class migration support |
| Navigation | go_router | Declarative, shell routes for adaptive layout, deep-link ready |
| HTTP client | Dio | Interceptors, retry logic, timeout handling |
| Market data | Yahoo Finance (unofficial JSON) + Stooq CSV fallback | Yahoo primary; Stooq CSV (`f=sdc`) used when Yahoo returns no data |
| Currency rates | Frankfurter (api.frankfurter.app) | Free, no API key, ECB data, cacheable, supports major ISO 4217 pairs |
| Nextcloud sync | WebDAV over HTTP | Nextcloud's native protocol; no extra server needed |
| Backup / restore | archive + xml (custom BackupService) | ZIP (JSON) for sync backup; ODS for human-readable export |
| Push notifications | firebase_messaging | Android FCM only (per requirements) |
| Background tasks | WorkManager (via workmanager plugin) | Android only; polls prices when app is closed |
| Local notifications | flutter_local_notifications | All platforms; used for alerts on desktop |
| Secure storage | flutter_secure_storage | Nextcloud credentials, encrypted at rest |

---

## 2. Project Structure

```
lib/
├── main.dart
├── app.dart                        # MaterialApp, theme, go_router bootstrap
│
├── core/
│   ├── database/
│   │   ├── app_database.dart       # Drift database root
│   │   ├── tables/                 # One file per table definition
│   │   └── daos/                   # One DAO per aggregate (stocks, dividends…)
│   ├── services/
│   │   ├── market_data_service.dart
│   │   ├── currency_service.dart
│   │   ├── nextcloud_service.dart
│   │   ├── backup_service.dart
│   │   └── notification_service.dart
│   ├── models/                     # Immutable domain models (pure Dart, no Flutter)
│   ├── calculators/                # P&L, avg price, dividend yield — pure functions
│   └── utils/                      # Formatting, date helpers, decimal math
│
├── features/
│   ├── dashboard/
│   ├── stocks/
│   ├── transactions/
│   ├── dividends/
│   ├── brokers/
│   └── settings/
│
└── shell/
    ├── adaptive_shell.dart         # Picks mobile or desktop shell by screen width
    ├── mobile_shell.dart           # Bottom navigation bar
    └── desktop_shell.dart          # Persistent sidebar + content area
```

Each feature folder follows the same internal layout:

```
features/<name>/
├── <name>_screen.dart          # Widget(s)
├── <name>_provider.dart        # Riverpod providers (state + async data)
└── widgets/                    # Feature-local reusable widgets
```

---

## 3. Data Model

### 3.1 Tables

**brokers**
| Column | Type | Notes |
|---|---|---|
| id | UUID (PK) | |
| name | TEXT | |
| notes | TEXT? | |

**stocks**
| Column | Type | Notes |
|---|---|---|
| id | UUID (PK) | |
| broker_id | UUID (FK brokers) | |
| isin | TEXT (UNIQUE) | ISO 6166, e.g. US0378331005 |
| symbol | TEXT | e.g. AAPL — resolved from ISIN |
| name | TEXT | e.g. Apple Inc. — resolved from ISIN |
| exchange | TEXT | e.g. NASDAQ — resolved from ISIN |
| currency | TEXT | ISO 4217, e.g. USD — resolved from ISIN |
| drip_enabled | BOOL | Dividend reinvestment flag |

**transactions**
| Column | Type | Notes |
|---|---|---|
| id | UUID (PK) | |
| stock_id | UUID (FK stocks) | |
| type | ENUM | buy \| sell |
| executed_at | DATETIME | |
| shares | DECIMAL | |
| price_per_share | DECIMAL | |
| currency | TEXT | |
| fees | DECIMAL | default 0 |
| notes | TEXT? | |

**stock_splits**
| Column | Type | Notes |
|---|---|---|
| id | UUID (PK) | |
| stock_id | UUID (FK stocks) | |
| date | DATE | |
| from_shares | INT | e.g. 1 |
| to_shares | INT | e.g. 4 → ratio 4:1 |

**dividends**
| Column | Type | Notes |
|---|---|---|
| id | UUID (PK) | |
| stock_id | UUID (FK stocks) | |
| type | ENUM | paid \| expected |
| date | DATE | payment date or expected date |
| amount_per_share | DECIMAL | |
| total_amount | DECIMAL? | null for expected (estimated on display) |
| currency | TEXT | |
| withholding_tax | DECIMAL? | pre-filled from ISIN country; user-adjustable |
| notes | TEXT? | |
| source | ENUM | manual \| auto; default manual |
| confirmed | BOOL | false = awaiting user confirmation (auto paid only); default true |

**price_cache**
| Column | Type | Notes |
|---|---|---|
| stock_id | UUID (PK, FK stocks) | |
| price | DECIMAL | |
| currency | TEXT | |
| fetched_at | DATETIME | |
| manual_override | BOOL | default false; manual prices bypass the staleness TTL |

**exchange_rate_cache**
| Column | Type | Notes |
|---|---|---|
| base | TEXT (PK) | ISO 4217 |
| target | TEXT (PK) | ISO 4217 |
| rate | DECIMAL | |
| fetched_at | DATETIME | |
| manual_override | BOOL | bypass TTL when true |

**settings** (single row, id = 1)
| Column | Type |
|---|---|
| preferred_currency | TEXT |
| nextcloud_url | TEXT? |
| nextcloud_username | TEXT? |
| nextcloud_path | TEXT |
| theme | ENUM: system \| light \| dark |
| notifications_enabled | BOOL |
| price_alert_threshold_pct | DECIMAL |
| dividend_alert_days | INT |
| last_sync_at | DATETIME? |
| nextcloud_keep_exports | INT | number of remote backups to retain (default 5) |

> Nextcloud password is stored separately in flutter_secure_storage, not in SQLite.

---

## 4. Layered Architecture

```
┌──────────────────────────────────────────────┐
│              Presentation Layer              │
│   Flutter widgets + Riverpod UI providers   │
│   adaptive_shell  ·  feature screens        │
├──────────────────────────────────────────────┤
│               Domain Layer                   │
│          Pure Dart — no Flutter              │
│  models  ·  calculators  ·  business rules  │
├──────────────────────────────────────────────┤
│                Data Layer                    │
│          Repositories (one per aggregate)   │
├─────────────────────┬────────────────────────┤
│   Local (Drift/     │  Remote (Dio)          │
│   SQLite)           │  market data · FX ·    │
│                     │  Nextcloud WebDAV      │
└─────────────────────┴────────────────────────┘
```

Data always flows upward. Widgets never touch repositories directly — they go through Riverpod providers which call domain logic, which calls repositories.

---

## 5. Key Design Decisions

### 5.1 Adaptive Layout Breakpoint
At **≥ 600 dp** the `adaptive_shell` switches to the desktop shell (persistent sidebar). Below that the mobile shell (bottom navigation bar) is used. The breakpoint is implemented inside a `ShellRoute` in go_router so that navigation state and scroll positions are preserved across the switch.

### 5.2 Split-Adjusted Calculations
Raw transaction rows are never modified when a stock split is recorded. `PortfolioCalculator.calculate()` applies a cumulative split multiplier when reading historical transactions, keeping raw data immutable and auditable. The helper `PortfolioCalculator.splitMultiplierAfter(txDate, splits)` is a public static method so that `PnlCalculator` can share the same logic without duplication.

For historical queries (e.g. "how many shares did the user hold on dividend date D?"), `PortfolioCalculator.sharesAtDate(transactions, splits, asOf)` computes the position at a past date by filtering transactions to those on or before `asOf` and applying only the splits that occurred between each transaction date and `asOf`. This is used by `StockActions.syncDividends` to filter out dividends for periods when no shares were held.

### 5.3 Currency Conversion
Exchange rates are fetched on demand and cached with a 1-hour TTL. When offline, the most recent cached rate is used with a staleness indicator shown in the UI. Manual overrides stored in the database bypass the TTL entirely.

**Rate convention:** `ExchangeRate(base: preferred, target: other, rate: r)` where `r = preferredPerOther` — i.e. "how many preferred-currency units equal 1 unit of `other`". `ExchangeRate.convert(amount)` is simply `amount * rate`, which converts an `other`-denominated amount to the preferred currency. `CurrencyService` fetches from Frankfurter (`?from=preferredCurrency`), which returns `"1 preferred = X other"`. The stored rate is `1/X` (preferred per other), consistent with the convention.

The static method `ExchangeRate.find(rates, from, to)` is the canonical lookup: it returns the rate where `r.base == to && r.target == from`, or `null` if none exists or `from == to`.

**Two-step conversion in `portfolioSummaryProvider`:**
1. If `PriceQuote.currency` (the currency Yahoo Finance returns) differs from `stock.currency` (the unit of stored transaction prices), the quote price is first converted to `stock.currency`. This ensures `PnlCalculator` always sees consistent units — both `currentPrice` and `avgBuyPrice` in the same currency — so P&L and percentage figures are correct.
2. The resulting PnlResult (in `stock.currency`) is then converted to `preferredCurrency` for portfolio-level aggregation.

If either rate is missing, a `missingRate` badge is shown on the dashboard tile.

### 5.4 ISIN Lookup
When a user enters an ISIN, the app queries the **OpenFIGI API** (free, no auth required for basic use) to resolve the ticker symbol, company name, exchange, and currency. If multiple listings are found (e.g. a stock traded on several exchanges), a bottom-sheet picker lets the user choose — each listing shows a live price fetched in parallel. The resolved currency is pre-filled in the currency dropdown. The last-used broker is recalled from `flutter_secure_storage` and pre-selected. If the lookup fails (offline or unknown ISIN), the user can enter all fields manually. ISIN format is validated client-side (2-letter country code + 9 alphanumeric chars + 1 check digit using the Luhn-based ISO 6166 algorithm) before any network call is made. The currency field on the Edit Stock screen also allows the stored currency to be corrected after the fact.

### 5.5 Financial Arithmetic
All monetary values are stored and calculated as `Decimal` (via the `decimal` package), never `double`, to avoid floating-point rounding errors.

### 5.6 Background Price Alerts on Android
True FCM push requires a backend server to send messages. To avoid a server dependency, price alerts on Android are implemented using **WorkManager** (periodic background task, ~15 min minimum interval). The task fetches latest prices, checks thresholds, and fires a local notification if triggered. FCM infrastructure is included in the project so a self-hosted backend can be added later without client changes.

### 5.7 ODS Structure

The exported ODS file contains 7 sheets in the following order.

#### Sheet 1 — Summary

Key-value pairs, no fixed column count.

| Row | A | B |
|---|---|---|
| 1 | StockManager Export | _(app name / version)_ |
| 2 | Generated | ISO 8601 timestamp |
| 3 | Preferred currency | ISO 4217 code |
| 5 | Portfolio value | converted to preferred currency |
| 6 | Total invested | converted to preferred currency |
| 7 | Unrealised P&L | converted to preferred currency |
| 8 | Unrealised P&L % | percentage |
| 9 | Realised P&L | converted to preferred currency |
| 10 | Dividends received (all-time) | converted to preferred currency |
| 11 | Dividends received (current year) | converted to preferred currency |

#### Sheet 2 — Brokers

| A: Name | B: Notes |
|---|---|
| Scalable Capital | |
| Trade Republic | Main account |

#### Sheet 3 — Stocks

| Col | Field | Notes |
|---|---|---|
| A | ISIN | ISO 6166 |
| B | Ticker | e.g. AAPL |
| C | Name | e.g. Apple Inc. |
| D | Broker | broker name |
| E | Exchange | e.g. NASDAQ |
| F | Currency | native ISO 4217 |
| G | Shares held | decimal |
| H | Avg buy price | in native currency |
| I | Current price | in native currency |
| J | Current value | converted to preferred currency |
| K | Invested | converted to preferred currency |
| L | Unrealised P&L | converted to preferred currency |
| M | Unrealised P&L % | percentage |
| N | Dividend yield % | annual, percentage |
| O | DRIP | Yes / No |

#### Sheet 4 — Transactions

| Col | Field | Notes |
|---|---|---|
| A | Date | YYYY-MM-DD |
| B | Time | HH:MM |
| C | ISIN | |
| D | Ticker | |
| E | Name | |
| F | Broker | |
| G | Type | BUY / SELL |
| H | Shares | decimal |
| I | Price per share | in transaction currency |
| J | Currency | ISO 4217 |
| K | Fees | in transaction currency |
| L | Total cost | shares × price + fees |
| M | Notes | optional |

#### Sheet 5 — Dividends Paid

| Col | Field | Notes |
|---|---|---|
| A | Date | YYYY-MM-DD |
| B | ISIN | |
| C | Ticker | |
| D | Name | |
| E | Amount per share | in dividend currency |
| F | Shares | at time of payment |
| G | Total gross | E × F |
| H | Withholding tax | in dividend currency |
| I | Total net | G − H |
| J | Currency | ISO 4217 |
| K | Notes | optional |

#### Sheet 6 — Dividends Expected

| Col | Field | Notes |
|---|---|---|
| A | Expected date | YYYY-MM-DD |
| B | ISIN | |
| C | Ticker | |
| D | Name | |
| E | Amount per share (est.) | in dividend currency |
| F | Shares | current holding |
| G | Total estimated | E × F |
| H | Currency | ISO 4217 |

#### Sheet 7 — Exchange Rates

| Col | Field | Notes |
|---|---|---|
| A | Base currency | ISO 4217 |
| B | Target currency | ISO 4217 |
| C | Rate | decimal |
| D | Source | `live` or `manual override` |
| E | Fetched / set at | ISO 8601 timestamp |

### 5.8 Auto-Fetched Dividends

Tapping the sync icon on the Stock Detail screen calls `MarketDataService.fetchDividends(symbol)`, which queries two Yahoo Finance endpoints:
1. **Paid history** (`chart/{symbol}?events=dividends&range=5y`) — returns up to 5 years of ex-dividend events.
2. **Expected next dividend** (`quoteSummary/{symbol}?modules=calendarEvents`) — returns the next declared dividend date; the amount is estimated from the most recent paid dividend.

`StockActions.syncDividends` filters the results:
- Skips dates already present in the database (deduplication by stock ID + date).
- Skips dates when `PortfolioCalculator.sharesAtDate()` returns zero (the user held no shares).
- Pre-fills `totalAmount` as `amountPerShare × sharesAtDate` and `withholdingTax` from `withholdingTaxRate(isin)` (see below).
- Paid auto-fetched dividends are inserted with `confirmed = false` and shown in a "Pending confirmation" section requiring user review before inclusion in calculations.
- Expected dividends are inserted immediately as `confirmed = true` (they are estimates, not real cash flows).

#### Withholding tax pre-fill

`withholdingTaxRate(isin)` uses the two-character ISO 3166-1 country code embedded in the ISIN to look up standard dividend withholding tax (DBA) rates. Values are estimates based on common treaty rates for German retail investors and should be verified against broker tax documents. The function returns `Decimal.zero` for unrecognised country codes; users should manually enter the correct rate in that case.

### 5.9 Analyst Consensus Data

`MarketDataService.fetchAnalystData(symbol)` fetches four modules from Yahoo Finance's v10 `quoteSummary` API in a single request:

| Module | Fields extracted |
|---|---|
| `financialData` | `targetMeanPrice`, `targetLowPrice`, `targetHighPrice`, `recommendationKey`, `numberOfAnalystOpinions`, `financialCurrency` |
| `summaryDetail` | `fiftyTwoWeekLow`, `fiftyTwoWeekHigh`, `trailingPE`, `forwardPE` |
| `defaultKeyStatistics` | `trailingEps`, `52WeekChange` (stored as `yearChangePct`, a decimal fraction e.g. `0.157` = +15.7%) |
| `recommendationTrend` | `strongBuy`, `buy`, `hold`, `sell`, `strongSell` counts (most recent period) |

The result is an `AnalystData` model. It is exposed via `analystDataProvider` (a `FutureProvider.family` keyed by `stockId`) and displayed in two places:
- **Stock Detail** — full "Analysis" card with target prices, range bars, consensus breakdown, and valuation metrics.
- **Dashboard tile** — a compact coloured badge (Str.Buy / Buy / Hold / Undprf. / Sell) next to the ticker symbol, loaded silently in the background using the same keepAlive cache.

Data is not persisted locally.

#### Caching and manual refresh

`analystDataProvider` uses `ref.keepAlive()` with a 10-minute TTL, so navigating away and back does not trigger a full Yahoo round-trip on every visit. A `StateProvider.family<int, String>` counter (`analystRefreshProvider`) is used to force a re-fetch: `analystDataProvider` watches it, and the refresh button on the Analysis card increments it. `ref.invalidate()` is intentionally **not** used here because it interferes with the `keepAlive` link.

#### Yahoo Finance session (GDPR)

Accessing the quoteSummary API requires a valid session cookie set (`GUC`, `A1`, `A3`, etc.) and a `crumb` query parameter. EU users are redirected through a GDPR consent flow before reaching `finance.yahoo.com`. `_ensureSession()` handles this by:

1. Following the `finance.yahoo.com → guce.yahoo.com → consent.yahoo.com` redirect chain manually (`followRedirects: false`) and collecting `Set-Cookie` headers at each hop.
2. If the landing page contains a GDPR consent form, POSTing `csrfToken + sessionId + agree=agree` and following the post-consent redirect chain, again gathering cookies.
3. Fetching the crumb from `query2.finance.yahoo.com/v1/test/getcrumb` using the accumulated cookies.

Cookies are extracted directly from `Set-Cookie` response headers (not via a cookie jar) because the GDPR flow sets cookies on `consent.yahoo.com`, which a domain-scoped jar would not return for `finance.yahoo.com` requests. The session (cookie string + crumb) is cached for 55 minutes. A `Completer<void>` gate ensures concurrent callers wait on a single in-flight init rather than racing through the GDPR flow in parallel.

All authenticated `quoteSummary` requests (analyst data, expected dividend) use `_withYahooRetry` for automatic backoff on HTTP 429 (rate-limit) responses.

#### Analyst price currency conversion

Yahoo Finance returns analyst price targets in the stock's **trading currency** (the same denomination as the live price quote), regardless of what the `financialCurrency` field says. `financialCurrency` reflects the company's financial-reporting currency and is unreliable as a conversion key (e.g. CADLR.OL reports `financialCurrency=EUR` but all prices are in NOK). `AnalystData.financialCurrency` is stored for diagnostics only; it must not be used for currency conversion.

`_buildAnalystCard` therefore uses `quoteCurrency` (the currency of the cached `PriceQuote`) as the effective analyst currency. If `quoteCurrency ≠ stock.currency`, it calls `ExchangeRate.find(rates, quoteCurrency, stockCurrency)` to convert all monetary fields (target mean/low/high, 52-week range, EPS) before display. The `canCompare` flag controls whether upside/downside % and the position marker on range bars are shown (they require a successful conversion so that `currentPrice` and the analyst targets are in the same unit).

#### Analysis card UI

| Section | Details |
|---|---|
| Recommendation chip | Coloured chip: Strong Buy (dark green) · Buy (green) · Hold (amber) · Underperform (orange) · Sell/Strong Sell (red) |
| Target price | Mean target with upside/downside % in matching colour; low–high gradient range bar with current-price marker |
| 52-Week Range | Same gradient bar widget, same current-price marker |
| Consensus | Stacked colour bar (proportional to analyst counts) with a text legend |
| Valuation | Trailing P/E · Forward P/E · EPS (TTM), converted to stock currency |

### 5.10 Price History Chart and Change Badges

`MarketDataService.fetchPriceHistory(symbol, range)` fetches OHLCV closing prices from the Yahoo Finance v8 chart endpoint (`query1.finance.yahoo.com/v8/finance/chart/{symbol}`). It does not require a session crumb (the v8 endpoint accepts unauthenticated requests) but uses `_withYahooRetry` for 429 backoff. The currency is read from `meta.currency` in the response and embedded in every returned `PricePoint`.

| `ChartRange` | Yahoo `range` | Yahoo `interval` |
|---|---|---|
| 1D | `1d` | `5m` (intraday ticks) |
| 1W | `5d` | `1d` |
| 1M | `1mo` | `1d` |
| 6M | `6mo` | `1d` |
| 1Y | `1y` | `1wk` |
| 5Y | `5y` | `1wk` |
| MAX | `max` | `1mo` |

#### Provider

`priceHistoryProvider` is a `FutureProvider.family` keyed by `(stockId, ChartRange)`. It watches `stockByIdProvider(stockId)` so it automatically re-fetches when the stock's symbol changes (e.g. after an ISIN research update). Results are kept alive for **5 minutes** to avoid re-fetching during back-navigation and when the user cycles through range buttons.

#### `StockPriceChart` widget

A `ConsumerStatefulWidget` rendered on the Stock Detail screen. State: active `ChartRange` (default: 1M) and `_showConverted` currency toggle. Features:

- **Y-axis labels** — three price labels in compact currency format (e.g. `€1.23K`, `NOK 152`) on the left edge.
- **Tooltip** — shows exact formatted price and date on touch.
- **Range selector** — pill buttons at the bottom; selected range highlighted with `primaryContainer`.
- **Currency toggle** — appears in the header when the stock's trading currency differs from the user's preferred currency **and** a conversion rate exists. Two pills (native code · preferred code) switch the chart, Y-axis labels, and tooltip between currencies. Conversion uses the live `exchangeRatesProvider` rates; if rates are unavailable the toggle is hidden and native prices are shown.

#### Change badges

Three coloured percentage pills shown at the bottom of the info card on Stock Detail:

| Badge | Source | Notes |
|---|---|---|
| 1D | `PriceQuote.dayChangePct` from Yahoo `regularMarketChangePercent` | Falls back to first→last of the 1D intraday history (open-to-latest) when the quote came from Stooq or a manual override |
| 1W | Computed: `last / first − 1` over the 1W price history | Currency cancels in the ratio |
| 1Y | `AnalystData.yearChangePct × 100` from `defaultKeyStatistics.52WeekChange` | Yahoo returns a fraction; multiplied by 100 for display |

All three are ratios, so currency conversion is not needed — they remain correct regardless of whether the chart is showing native or preferred currency.

### 5.11 Manual Price Override

For securities not covered by Yahoo Finance or Stooq (e.g. non-exchange-traded funds), the user can set a price manually from the Stock Detail screen. Manual prices:

- Are stored in `price_cache` with `manual_override = true`.
- Are never marked stale (`PriceQuote.withStaleness()` returns `isStale: false` when `isManualOverride` is true).
- Appear in the UI with a `(manual)` tag next to the price.
- Take precedence over live market prices when both exist in `priceQuotesProvider`.
- Can be cleared via a "Clear manual price" button on the Stock Detail screen, which removes the `price_cache` row and updates `priceQuotesProvider` immediately.

`MarketDataService.fetchQuote()` accepts an optional `stockCurrency` parameter used for the Stooq fallback. `fetchQuotes()` accepts an optional `currencyByStockId` map so `DashboardScreen` can pass currencies in bulk.

### 5.12 Nextcloud Sync Strategy

#### Backup format
Sync uses a **ZIP archive** containing JSON files (`brokers.json`, `stocks.json`, `transactions.json`, `dividends.json`, `stock_splits.json`, `meta.json`). This is handled by `BackupService.exportToZip()` / `importFromBytes()`. A separate `BackupService.exportToOds()` produces a human-readable ODS spreadsheet for the manual export/share feature. The ZIP backup filename pattern is `stockmanager_backup_YYYY-MM-DD.zip`.

`importFromBytes()` auto-detects the format from the archive contents (presence of `meta.json` → ZIP backup; presence of `content.xml` → ODS import).

#### Sync triggers
`NextcloudSyncNotifier` (a Riverpod `NotifierProvider`) manages sync state and triggers:

| Trigger | Behaviour |
|---|---|
| App startup (4 s delay) | PROPFIND for latest backup; if remote is newer set `pendingRestore`; if PROPFIND fails (network error) silently proceed to upload; a `Timer` (not `Future.delayed`) is used so it can be cancelled on dispose |
| Credential save | `findRemoteBackup()` → dialog: Restore / Upload / Later; choice is executed before returning to settings |
| Data mutation | `dataVersionProvider` increments; sync debounced by 5 s |
| Manual "Backup now" tap | `syncNow()` called directly |

#### Credentials read pattern
`NextcloudSyncNotifier._credentials()` reads directly from the Drift DAO (bypassing `settingsProvider`) on every invocation. This prevents stale `FutureProvider` cache from being used after `saveSettings()` writes new credentials. `lastSyncAt` is persisted via a targeted `updateLastSyncAt(DateTime)` DAO call rather than a full `upsertSettings()` to avoid overwriting other columns with stale data.

#### Bidirectional conflict resolution
On startup and after a credential save the app calls `findLatestBackup()` (WebDAV PROPFIND) and compares `backupDate` with `settings.lastSyncAt`. If the remote backup is newer, `pendingRestore` is set in `NextcloudSyncState` and:
- A card is shown on the Nextcloud settings screen with "Restore from server" / "Dismiss".
- On first launch a dialog is shown immediately after credential save.
Auto-upload is **suppressed** while a restore is pending user decision.

On "Restore": `downloadFile()` fetches the ZIP bytes and `importFromBytes()` replaces all local data atomically inside a Drift transaction. `lastSyncAt` is updated in settings. If the restore fails the screen stays open to display the error.

#### Backup retention
After every successful upload, `_pruneOldBackups` lists the remote directory, filters files matching the backup pattern, sorts newest-first, and deletes all beyond `AppSettings.nextcloudKeepExports` (default: 5). This is best-effort — individual delete failures are ignored.

#### Secure storage keys
| Key | Value |
|---|---|
| `nextcloud_password` | Nextcloud password / app token |
| `nextcloud_cert_fingerprint` | Pinned SHA-256 fingerprint for self-signed certs |
| `last_used_broker_id` | Pre-selects broker on the Add Stock screen |

### 5.13 Self-Signed Certificate Support
The Nextcloud HTTP client (Dio) is configured with a custom `HttpClient` that supports self-signed certificates via explicit certificate pinning:
1. On first connection to a new server URL, the app fetches the server's certificate and presents its fingerprint (SHA-256) to the user for manual confirmation.
2. On confirmation, the fingerprint is stored in `flutter_secure_storage`.
3. All subsequent WebDAV requests validate against the stored fingerprint; a mismatch aborts the connection and alerts the user.
4. The certificate can be re-pinned or removed from the Nextcloud settings screen.

This approach avoids globally disabling TLS verification — only the explicitly approved certificate is trusted.

---

## 6. Navigation Map

```
/                        → Dashboard
/stocks                  → Stock list
/stocks/:id              → Stock detail
/stocks/:id/edit         → Edit stock
/stocks/add              → Add stock
/stocks/:id/transactions/add              → Add transaction
/stocks/:id/transactions/:txId/edit       → Edit / delete transaction
/stocks/:id/dividends/add                 → Add dividend (paid or expected)
/stocks/:id/dividends/:divId/edit         → Edit / delete dividend
/dividends               → Dividend overview
/brokers                 → Broker list
/brokers/add             → Add broker
/brokers/:id/edit        → Edit broker
/settings                → Settings
/settings/backup         → Local backup (export / import ZIP)
/settings/nextcloud      → Nextcloud configuration
/settings/currency       → Currency preferences & overrides
/settings/notifications  → Notification preferences
/settings/about          → App version and GPL-3 licence
```

All routes are nested inside the `ShellRoute` so the navigation chrome (sidebar / bottom bar) is always present.
