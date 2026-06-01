# StockManager — Architecture

## 1. Technology Stack

| Concern | Library / Tool | Rationale |
|---|---|---|
| Framework | Flutter (Dart) | Single codebase for Android + macOS + Windows + Ubuntu |
| State management | Riverpod | Async-first, composable providers, easy to unit-test |
| Local database | Drift (SQLite) | Type-safe, reactive streams, first-class migration support |
| Navigation | go_router | Declarative, shell routes for adaptive layout, deep-link ready |
| HTTP client | Dio | Interceptors, retry logic, timeout handling |
| Market data | Yahoo Finance (unofficial JSON) + Stooq CSV fallback + Finnhub (optional) | Yahoo primary for live prices; Stooq CSV fallback for quotes; Finnhub selectable for analyst data (requires free API key) |
| Currency rates | Frankfurter (api.frankfurter.app) | Free, no API key, ECB data, cacheable, supports major ISO 4217 pairs |
| Nextcloud sync | WebDAV over HTTP | Nextcloud's native protocol; no extra server needed |
| Backup / restore | archive + xml (custom BackupService) | ZIP (JSON) for sync backup; ODS for human-readable export |
| Background tasks | WorkManager (via workmanager plugin) | Android only; price, rating, dividend, and trailing stop-loss checks when app is closed |
| Local notifications | flutter_local_notifications | All platforms; WorkManager fires them on Android, running app fires them on desktop |
| Secure storage | flutter_secure_storage | `last_used_broker_id` only; credentials moved to SQLite settings table |
| Markdown rendering | flutter_markdown | Renders AI analysis responses in the portfolio analysis screen |
| AI analysis | Anthropic Claude / Groq / Gemini (user-selectable) | SSE streaming via Dio; provider and model stored in settings; abstract `LlmService` interface |

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
│   │   ├── notification_service.dart
│   │   ├── background_check_service.dart
│   │   ├── log_service.dart
│   │   ├── llm_service.dart            # Abstract LlmService interface + LlmProvider enum + model lists
│   │   ├── claude_service.dart         # Anthropic SSE streaming implementation
│   │   ├── groq_service.dart           # Groq (OpenAI-compatible) SSE streaming
│   │   └── gemini_service.dart         # Google Gemini SSE streaming
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
│   ├── analysis/                       # AI portfolio analysis
│   │   ├── analysis_screen.dart        # Prompt chips, streaming response, ISIN suggestions
│   │   ├── analysis_provider.dart      # AnalysisNotifier, StockSuggestion, portfolio serialisation
│   │   └── ai_analysis_settings_screen.dart  # Provider / key / model picker
│   └── settings/
│       ├── about_screen.dart           # Version, GPL-3, privacy policy, app logs links
│       ├── broker_import_screen.dart   # Broker import entry-point (scaffold)
│       ├── flatex_import_screen.dart   # Flatex CSV import (parse → preview → import)
│       ├── privacy_policy_screen.dart  # In-app privacy policy
│       ├── logs_screen.dart            # Log viewer with share/clear
│       └── parsers/
│           └── flatex_order_parser.dart  # FlatexOrderParser, FlatexParsedOrder, FlatexUnpricedOrder
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

Notable provider files:

| File | Key exports |
|---|---|
| `features/dividends/dividends_provider.dart` | `estimatedAnnualDividendProvider`, `DividendEstimate` |

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
| asset_type | TEXT | `stock` \| `etf` \| `bond` \| `crypto` \| `other`; default `stock` |
| last_known_consensus | TEXT? | Most recent analyst `recommendationKey`; used by `BackgroundCheckService` to detect rating changes between runs |
| trailing_stop_pct | TEXT? (DECIMAL) | Drop threshold in percent (e.g. `10` = −10%); null = alert disabled |
| trailing_stop_high_water | TEXT? (DECIMAL) | Peak price in `stock.currency` recorded since the alert was enabled; null = not yet seeded (set on first background check after enabling) |

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
| notes | TEXT? | Free-form; `"Price estimated from historic closing price"` marks KVG draft imports |
| external_ref | TEXT? | Broker order number; used for deduplication on re-import (schema v14) |

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
| Column | Type | Notes |
|---|---|---|
| preferred_currency | TEXT | ISO 4217; default EUR |
| nextcloud_url | TEXT? | |
| nextcloud_username | TEXT? | |
| nextcloud_path | TEXT | default /StockManager/ |
| theme | ENUM: system \| light \| dark | |
| notifications_enabled | BOOL | |
| price_alert_threshold_pct | DECIMAL | |
| dividend_alert_days | INT | |
| last_sync_at | DATETIME? | |
| nextcloud_keep_exports | INT | remote backups to retain; default 5 |
| sparkline_range | TEXT | `ChartRange.label` (e.g. `1M`); default `1M` |
| market_data_provider | TEXT: yahoo \| finnhub | default yahoo |
| nextcloud_password | TEXT? | Nextcloud password / app token (moved from flutter_secure_storage) |
| finnhub_api_key | TEXT? | Finnhub API key (moved from flutter_secure_storage) |
| nextcloud_cert_fingerprint | TEXT? | Pinned SHA-256 cert fingerprint (moved from flutter_secure_storage) |
| claude_api_key | TEXT? | Anthropic Claude API key (schema v11) |
| claude_model | TEXT | Selected Claude model; default `claude-opus-4-7` (schema v11) |
| llm_provider | TEXT | Active AI provider: `claude` \| `groq` \| `gemini`; default `claude` (schema v12) |
| groq_api_key | TEXT? | Groq API key (schema v12) |
| gemini_api_key | TEXT? | Google Gemini API key (schema v12) |
| groq_model | TEXT | Selected Groq model; default `llama-3.3-70b-versatile` (schema v13) |
| gemini_model | TEXT | Selected Gemini model; default `gemini-2.0-flash` (schema v13) |

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

The `NavigationRail` inside `DesktopShell` uses **extended mode** (icons + labels, ~220 dp wide) only at **≥ 1200 dp**; between 600 and 1199 dp it shows icons only (~72 dp), which preserves usable screen space on tablets and landscape phones.

`AdaptiveShell` is a `ConsumerStatefulWidget`. Its `initState` registers a `ref.listenManual` subscription on `nextcloudSyncProvider` that detects when `pendingRestore` transitions from null to non-null (startup backup check) and shows a proactive restore dialog. A `_restoreDialogShowing` guard prevents concurrent dialogs if the state transitions rapidly. The listener is cancelled in `dispose`. The dialog is suppressed when the Nextcloud settings screen is already open (it handles the decision inline).

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
When a user enters an ISIN, the app queries the **OpenFIGI API** (free, no auth required for basic use) to resolve the ticker symbol, company name, exchange, and currency. If multiple listings are found (e.g. a stock traded on several exchanges), a bottom-sheet picker lets the user choose — each listing shows a live price fetched in parallel. The resolved currency is pre-filled in the currency dropdown. The last-used broker is recalled from `flutter_secure_storage` and pre-selected. If the lookup fails (offline or unknown ISIN), the user can enter all fields manually.

**`IsinLookupService.lookup()` return contract:**
- `null` — connection-layer failure (DNS, timeout, no internet). The caller surfaces "Connection failed. Check your internet connection."
- `[]` (empty list) — the server responded but found no listings for the ISIN (valid ISIN, unknown on OpenFIGI), or an HTTP 4xx/5xx response was received. The caller surfaces "No listings found for this ISIN."
- `List<IsinLookupResult>` (non-empty) — at least one listing was found.

Always check `null` and `isEmpty` separately. Using `results?.firstOrNull` collapses both failure modes and masks network errors.

ISIN format is validated client-side (2-letter country code + 9 alphanumeric chars + 1 check digit using the Luhn-based ISO 6166 algorithm) before any network call is made. The currency field on the Edit Stock screen also allows the stored currency to be corrected after the fact.

### 5.5 Financial Arithmetic
All monetary values are stored and calculated as `Decimal` (via the `decimal` package), never `double`, to avoid floating-point rounding errors.

### 5.6 Background Checks on Android
True FCM push requires a backend server to send messages. To avoid a server dependency, background checks on Android are implemented using **WorkManager** (periodic background task, ~15 min minimum interval, network required). The task is registered in `main.dart` via a top-level `callbackDispatcher` and dispatched to `BackgroundCheckService.run()`.

**WorkManager initialisation:** WorkManager's built-in `WorkManagerInitializer` ContentProvider is disabled in the Android manifest via `tools:node="remove"` on the `InitializationProvider` meta-data entry. This prevents a pre-Flutter ContentProvider crash on some devices. `Workmanager().initialize()` is called manually from Dart during `_main()`. The call is wrapped in a try-catch; a failure (e.g. pigeon channel not yet ready) is non-fatal — the app continues with background checks disabled and logs `WorkManager init failed` to the debug log.

`AppDatabase.background(file)` — used inside the WorkManager isolate — opens the SQLite file directly with `NativeDatabase(file)` on the calling isolate (not via `LazyDatabase`), bypassing the plugin registration issue that affects `NativeDatabase.createInBackground`.

The production `_openConnection()` (used by `AppDatabase()`) also uses `NativeDatabase(file)` directly, not `NativeDatabase.createInBackground()`. The background variant spawns a Dart isolate that does not inherit Flutter plugin registrations, so `sqlite3_flutter_libs` cannot load `libsqlite3.so` there, causing a SIGABRT in release builds.

`BackgroundCheckService` is a static-only class that runs inside a WorkManager isolate (no Riverpod). It opens its own `AppDatabase.background(file)` connection and `MarketDataService` + `FlutterLocalNotificationsPlugin` instances, then performs the following checks:

**Every cycle (every ~15 min):**
- **Price alert** — fetches a fresh quote via `MarketDataService`, compares against the cached `price_cache` price; fires a `price_alerts` channel notification if the change exceeds `priceAlertThresholdPct`. The cached price is updated after each run so the next comparison is against the most recently seen price.
- **Trailing stop-loss** — if `trailing_stop_pct` is set for a stock, the quote price is first converted to `stock.currency` using the cached exchange rate (`settingsDao.getRate(stock.currency, quote.currency)`). If the converted price exceeds the current `trailing_stop_high_water`, the high-water mark is updated. If it falls to or below `highWater × (1 − pct/100)`, a `stop_loss_alerts` notification fires and the high-water is reset to null so the alert does not re-fire until the price recovers and makes a new peak. The stop check is skipped when no exchange rate is cached (avoids cross-currency comparisons).

**Once per calendar day** (gated by `background_check_last_run.txt` in app documents):
- **Analyst rating change** — fetches analyst data (Finnhub or Yahoo based on `settings.marketDataProvider`), compares `recommendationKey` against `stocks.lastKnownConsensus`; fires a `rating_alerts` channel notification on change, then calls `StocksDao.updateLastKnownConsensus()` to persist the new value. No notification is sent on the first run (when `lastKnownConsensus` is null), preventing false alerts at install time.
- **Dividend alert** — queries expected dividends within the next `dividendAlertDays` days; fires a `dividend_alerts` channel notification for each upcoming payment.

Rating and dividend checks are gated to once per day to avoid hammering the analyst API (~100 HTTP requests per 15-min cycle for a full portfolio) and to prevent the same dividend notification firing repeatedly.

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
| `financialData` | `targetMeanPrice`, `targetLowPrice`, `targetHighPrice`, `recommendationKey`, `numberOfAnalystOpinions`, `financialCurrency`, `freeCashflow` (numerator for FCF yield) |
| `summaryDetail` | `fiftyTwoWeekLow`, `fiftyTwoWeekHigh`, `trailingPE`, `forwardPE`, `fiveYearAvgDividendYield` (already in %, e.g. 3.5 = 3.5%), `trailingAnnualDividendRate` (annual dividend per share in trading currency), `marketCap` (denominator for FCF yield) |
| `defaultKeyStatistics` | `trailingEps`, `52WeekChange` (stored as `yearChangePct`, a decimal fraction e.g. `0.157` = +15.7%), `enterpriseToEbitda` (EV/EBITDA multiple), `priceToBook` (P/B ratio), `pegRatio` (PEG ratio) |
| `recommendationTrend` | `strongBuy`, `buy`, `hold`, `sell`, `strongSell` counts (most recent period) |

`MarketDataService.fetchAnalystDataFromFinnhub(symbol, apiKey)` fires three parallel requests to Finnhub's v1 API: `/stock/price-target` (mean/low/high targets), `/stock/recommendation` (consensus counts for the most recent period), and `/stock/metric?metric=all` (52-week range, P/E, EPS, 5Y dividend yield, annual dividend per share, plus the additional valuation metrics below). A weighted recommendation score `(strongBuy×2 + buy − sell − strongSell×2) / total` is mapped to the same `strong_buy / buy / hold / sell / strong_sell` keys used by Yahoo. Finnhub's `52WeekPriceReturnDaily` is in percent and is divided by 100 to match Yahoo's fraction convention for `yearChangePct`.

Additional valuation metrics sourced from Finnhub's `metric` map:

| Field | Finnhub metric key(s) | Notes |
|---|---|---|
| `evToEbitda` | `enterpriseValue` ÷ `ebitdaTTM` | Both in USD millions; ratio computed client-side; null if either is missing or zero |
| `priceToBook` | `pbQuarterly` | Direct field |
| `pegRatio` | `pegNormalizedAnnual` | Direct field |
| `freeCashFlowYield` | `freeCashFlowTTM` ÷ `marketCapitalization` | Both in USD millions; null if either is missing or zero |

`MarketDataService.fetchAnalystDataFinnhubWithFallback(symbol, apiKey)` runs both Finnhub and Yahoo requests in parallel and merges the results: Finnhub fields take precedence; any null fields (common for non-US stocks, e.g. `fiveYearAvgDividendYield`, `trailingAnnualDividendRate`) are filled from the Yahoo result. If Finnhub returns no data, the full Yahoo result is used. This method is called by `analystDataProvider` when Finnhub is the active provider.

The result is an `AnalystData` model. It is exposed via `analystDataProvider` (a `FutureProvider.family` keyed by `stockId`) and displayed in two places:
- **Stock Detail** — full "Analysis" card with target prices, range bars, consensus breakdown, and valuation metrics.
- **Dashboard tile** — a compact coloured badge (Str.Buy / Buy / Hold / Undprf. / Sell) next to the ticker symbol, loaded silently in the background using the same keepAlive cache.

Data is not persisted locally.

#### Caching and manual refresh

`analystDataProvider` uses `ref.keepAlive()` with a 10-minute TTL, so navigating away and back does not trigger a full Yahoo round-trip on every visit. A `StateProvider.family<int, String>` counter (`analystRefreshProvider`) is used to force a re-fetch: `analystDataProvider` watches it, and the refresh button on the Analysis card increments it. `ref.invalidate()` is intentionally **not** used here because it interferes with the `keepAlive` link. It also watches `analystCacheVersionProvider` (a `StateProvider<int>`) which is incremented when the market data provider is switched or the Finnhub API key is changed, busting all cached analyst data so the next open re-fetches from the new source.

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
| Valuation | Trailing P/E · Forward P/E · EPS (TTM) · EV/EBITDA · P/B ratio · PEG ratio · FCF yield; all converted to stock currency where applicable. FCF yield is displayed as a percentage (fraction × 100). Rows are omitted when the value is null (e.g. EV/EBITDA for stocks not covered by the chosen provider). |
| Dividends | Annual rate (`trailingAnnualDividendRate`, hidden when zero/null) · 5Y avg yield (`fiveYearAvgDividendYield`, %) · Est. annual income (shares × current price × 5Y yield ÷ 100, in stock currency, shown when shares > 0 and yield is available) |

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
- **Transaction overlays** — buy and sell transactions within the visible date range are rendered as coloured dots on the price line (green for buys, red for sells). Each dot is placed at the nearest available price point by date using `_nearestPointIndex`. Touching near a dot appends a tooltip item showing the transaction type, share count, and price per share. Dots from overlay bars that are more than 2 data points from the current touch position are suppressed to avoid fl_chart's "always include nearest spot from every bar" behaviour.
- **Range-switch stability** — the chart is wrapped in `KeyedSubtree(key: ValueKey(_range))`. This forces fl_chart to rebuild its internal state from scratch on every range change, preventing an animation crash that occurs when the new range has a different number of data points than the previous one.

#### Change badges

Three coloured percentage pills shown at the bottom of the info card on Stock Detail:

| Badge | Source | Notes |
|---|---|---|
| 1D | `PriceQuote.dayChangePct` from Yahoo `regularMarketChangePercent` | Falls back to first→last of the 1D intraday history (open-to-latest) when the quote came from Stooq or a manual override |
| 1W | Computed: `last / first − 1` over the 1W price history | Currency cancels in the ratio |
| 1Y | `AnalystData.yearChangePct × 100` from `defaultKeyStatistics.52WeekChange` | Yahoo returns a fraction; multiplied by 100 for display |

All three are ratios, so currency conversion is not needed — they remain correct regardless of whether the chart is showing native or preferred currency.

### 5.11 Dashboard Sparklines

Each stock tile on the Dashboard shows a 72×36 px mini line chart (sparkline) to the right of the name column. The sparkline fetches price history via the same `priceHistoryProvider` used by `StockPriceChart`, so the result is cached for 5 minutes and shared if the Stock Detail screen has already loaded the same range.

**Configurable range:** The time window is controlled by `AppSettings.sparklineRange` (default: 1M). The user selects a range in Settings → Display → "Sparkline period", which opens a `SimpleDialog` listing all seven `ChartRange` values with a checkmark on the active choice. The dialog uses the builder context `ctx` for `Navigator.pop` — **not** the outer screen context — because `showDialog` defaults to `useRootNavigator: true` and the two navigators are different inside a `ShellRoute`. Changing the setting immediately updates all visible sparklines because tiles watch `settingsStreamProvider`.

**Colour:** Green (`Colors.green.shade600`) when the last price in the period ≥ the first price; red (`colorScheme.error`) otherwise. The area below the line is filled with the same colour at 15 % opacity.

**Rendering:** `duration: Duration.zero` (no animation), no axes, no grid, no border, touch interaction disabled. The sparkline is hidden while the fetch is in progress or when fewer than two data points are available.

### 5.11b Stocks Screen Search and Sort



`StocksScreen` is a `ConsumerStatefulWidget` that adds search and sort on top of `stocksStreamProvider`:

- **Search** — a persistent `TextField` at the top of the body filters the list in real-time by symbol or name (case-insensitive `contains`). A clear button (✕) appears when the field is non-empty.
- **Sort** — a `PopupMenuButton` in the AppBar offers three orderings:
  - **Symbol** (A → Z, default)
  - **Name** (A → Z)
  - **Price high → low** — uses the raw `PriceQuote.price`; stocks with no quote sort last. *Note: the price is not normalised to a common currency, so cross-currency comparisons are ordinal only.*
- The active sort option is marked with a checkmark in the popup. Filtering and sorting are applied together in `_applyFilterAndSort` and produce a new list on every build (O(n log n), negligible for portfolio sizes).

### 5.11c Dashboard Closed-Position Filter

A **visibility toggle** in the Dashboard AppBar (eye icon) lets the user hide positions where `sharesHeld ≤ 0` — i.e. stocks that have been fully sold but whose records still exist in the database. State is local `_hideClosedPositions: bool` in `_DashboardScreenState`.

When the filter is active:
- `summary.stockItems` is filtered with `.where((i) => i.sharesHeld.isPositive)` before rendering.
- The "Holdings" header shows a `(N closed hidden)` suffix so the user knows the list is filtered.
- If all positions are closed and the filter is on, a "All positions are closed." placeholder replaces the card.
- The icon switches to `visibility_off` while the filter is active.

The filter does **not** affect `PortfolioSummaryCard` or `AllocationChart` — those always aggregate the full `PortfolioSummary`.

### 5.11d Stock Detail Pull-to-Refresh

`StockDetailScreen` wraps its `ListView` in a `RefreshIndicator`. Pulling down calls `_fetchPrice(forceRefresh: true)`, which always fetches a fresh quote regardless of cache staleness (unlike the on-load call which skips when a non-stale quote is already in memory). On network failure during a manual refresh, a `SnackBar` with "Could not refresh price" is shown; silent failure is reserved for the background on-load fetch.

### 5.12 Manual Price Override

For securities not covered by Yahoo Finance or Stooq (e.g. non-exchange-traded funds), the user can set a price manually from the Stock Detail screen. Manual prices:

- Are stored in `price_cache` with `manual_override = true`.
- Are never marked stale (`PriceQuote.withStaleness()` returns `isStale: false` when `isManualOverride` is true).
- Appear in the UI with a `(manual)` tag next to the price.
- Take precedence over live market prices when both exist in `priceQuotesProvider`.
- Can be cleared via a "Clear manual price" button on the Stock Detail screen, which removes the `price_cache` row and updates `priceQuotesProvider` immediately.

`MarketDataService.fetchQuote()` accepts an optional `stockCurrency` parameter used for the Stooq fallback. `fetchQuotes()` accepts an optional `currencyByStockId` map so `DashboardScreen` can pass currencies in bulk.

### 5.13 Nextcloud Sync Strategy

#### Backup format
Sync uses a **ZIP archive** containing JSON files (`brokers.json`, `stocks.json`, `transactions.json`, `dividends.json`, `stock_splits.json`, `meta.json`). This is handled by `BackupService.exportToZip()` / `importFromBytes()`. A separate `BackupService.exportToOds()` produces a human-readable ODS spreadsheet for the manual export/share feature. Both `exportToZip()` and `exportToOds()` wrap all five DAO reads in a single `_db.transaction()` call to guarantee an atomic consistent snapshot. Without this, a stock added concurrently between the stocks-read and transactions-read would appear in the transactions file but not the stocks file, causing FK constraint errors (or silent row drops) on the next restore.

The ZIP backup filename pattern is `stockmanager_backup_YYYY-MM-DDTHH-MM-SSZ.zip` (full UTC timestamp; colons replaced with hyphens for filesystem compatibility). `findLatestBackup` and `_pruneOldBackups` also accept the legacy `YYYY-MM-DD` date-only format for backward compatibility with older backups already on the server.

On desktop platforms (macOS, Windows, Linux), `LocalBackupScreen` uses `FilePicker.platform.saveFile()` to present a native save dialog. On mobile it uses `SharePlus.instance.share()` as before.

`importFromBytes()` auto-detects the format from the archive contents (presence of `meta.json` → ZIP backup; presence of `content.xml` → ODS import).

#### Sync triggers
`NextcloudSyncNotifier` (a Riverpod `NotifierProvider`) manages sync state and triggers:

| Trigger | Behaviour |
|---|---|
| App startup (4 s delay) | `_checkAndSync()`: PROPFIND for latest backup; if remote is newer than `lastSyncAt` → sets `pendingRestore` (suppresses auto-upload); if PROPFIND fails → proceeds to upload. A `Timer` (not `Future.delayed`) is used so it can be cancelled on dispose. |
| `pendingRestore` set (any trigger) | `AdaptiveShell` listener detects the null→non-null transition and shows a proactive restore/later dialog — unless the Nextcloud settings screen is already open. |
| Credential save | `checkForRemoteBackup()` → sets `pendingRestore` if server has a newer backup (reads `lastSyncAt` directly from DAO, not stale provider cache); inline dialog on the settings screen offers Restore / Upload current data / Later. `dismissRestore()` is called before `syncNow()` to clear the guard. |
| Data mutation | `dataVersionProvider` increments; sync debounced by 5 s |
| Manual "Backup now" tap | `syncNow()` called directly |

#### Credentials read pattern
`NextcloudSyncNotifier._credentials()` reads directly from the Drift DAO (bypassing `settingsProvider`) on every invocation. This prevents stale `FutureProvider` cache from being used after `saveSettings()` writes new credentials. `lastSyncAt` is persisted via a targeted `updateLastSyncAt(DateTime)` DAO call rather than a full `upsertSettings()` to avoid overwriting other columns with stale data.

#### Bidirectional conflict resolution
On startup and after a credential save, `findLatestBackup()` (WebDAV PROPFIND) compares `backupDate` with `lastSyncAt`. If the remote backup is newer, `pendingRestore` is set in `NextcloudSyncState`. This triggers two UI surfaces:
- **Proactive dialog** — `AdaptiveShell` listens on `nextcloudSyncProvider` and shows a modal "Server backup found / Restore from server? / Later" dialog wherever the user currently is (suppressed on the Nextcloud settings screen itself).
- **Inline card** — the Nextcloud settings screen always shows a card when `pendingRestore != null`, with "Restore from server" / "Dismiss" buttons.

Auto-upload is **suppressed** while a restore is pending user decision.

On "Restore": `downloadFile()` fetches the ZIP bytes and `importFromBytes()` replaces all local data atomically inside a Drift transaction. `lastSyncAt` is updated in settings. `importFromBytes()` returns an `int` skip count — the number of child rows (transactions, dividends, splits) that could not be restored because their parent stock was absent from the backup (a race condition in backups created before the atomic-export fix). Both the local backup screen and the Nextcloud sync state surface a visible warning to the user when `skipped > 0` so no data is silently lost.

#### Backup retention
After every successful upload, `_pruneOldBackups` lists the remote directory, filters files matching the backup pattern, sorts newest-first, and deletes all beyond `AppSettings.nextcloudKeepExports` (default: 5). This is best-effort — individual delete failures are ignored.

#### Secure storage keys
| Key | Value |
|---|---|
| `last_used_broker_id` | Pre-selects broker on the Add Stock screen |

`nextcloud_password`, `nextcloud_cert_fingerprint`, and `finnhub_api_key` were previously stored in `flutter_secure_storage` and are now columns in the `settings` table (schema v7–v8). This removed the dependency on the macOS Data Protection Keychain, which requires a real Team ID and fails on ad-hoc signed builds.

### 5.15 Portfolio Allocation Chart

`AllocationChart` is a `StatefulWidget` rendered on the Dashboard screen between the portfolio summary card and the holdings list.

**Data source:** `PortfolioSummary.stockItems` (already computed by `portfolioSummaryProvider`). Each `StockSummaryItem.currentValue` is in the user's preferred currency because `portfolioSummaryProvider` converts via `ExchangeRate`. Items where `missingRate = true` are excluded — their `currentValue` is in the stock's native currency and would corrupt the percentages.

**Slices:** Stocks are sorted by `currentValue` descending. The top 7 are individual slices; the remainder are grouped as "Others". A fixed 8-colour palette is used so slice colours are stable across sessions.

**Interaction:** Tapping a slice expands its radius (`46 → 56 dp`) via fl_chart's `PieTouchData`. The legend alongside shows each symbol and its percentage of the total, computed with `Decimal` arithmetic.

**Empty state:** The widget returns `SizedBox.shrink()` when no stock has both a price and a valid exchange rate, so the card never appears as an empty placeholder.

### 5.16 Dividend Income Chart

`DividendIncomeChart` is a `ConsumerStatefulWidget` rendered at the top of the Dividends screen.

**Data source:** `allDividendsProvider` (a `FutureProvider` that re-fires when `dataVersionProvider` increments). Only dividends with `type = paid`, `confirmed = true`, and `netAmount > 0` are included.

**Currency conversion:** Each dividend's `netAmount` is converted to the preferred currency using `ExchangeRate.find(rates, d.currency, preferred)`. Dividends whose currency cannot be converted (no rate available and currency differs from preferred) are **skipped** — including them raw would silently mix currencies in the bar totals.

**Grouping:** Dividends are bucketed by a period key — `"YYYY-MM"` in monthly mode, `"YYYY"` in yearly mode. Buckets are sorted chronologically (string sort on the zero-padded key is equivalent to date sort). A Monthly / Yearly toggle in the card header switches between modes; the toggle state is local `ConsumerState`.

**Chart rendering:** A `BarChart` from fl_chart. Bar width adapts to the number of periods (14 dp ≤ 12 bars, 9 dp ≤ 24, 6 dp otherwise). X-axis labels use a dynamic skip interval (every bar, every 3rd, or every 6th) and format as `"MMM"` for ≤ 12 bars or `"MMM 'yy"` for more. The y-axis shows compact currency labels (e.g. `€1.2k`). Tapping a bar shows a tooltip with the full period label and formatted total.

**Empty state:** Returns `SizedBox.shrink()` when there are no paid+confirmed dividends (e.g. new user, or all dividends are expected only), so the card never appears as an empty placeholder.

### 5.17 Estimated Annual Dividend Provider

`estimatedAnnualDividendProvider` is a synchronous `Provider` (not a `FutureProvider`) defined in `features/dividends/dividends_provider.dart`. It derives the portfolio-wide estimated annual dividend income entirely from already-cached data — no extra API calls are made.

**Data sources:**
- `portfolioSummaryProvider` — supplies `currentValue` (in preferred currency) and `sharesHeld` per stock.
- `analystDataProvider(stockId)` — read from the in-memory keepAlive cache for each stock; stocks where the provider has not yet resolved or returned an error are simply skipped.

**Computation:** For each stock that has cached `AnalystData` with a non-null, non-zero `fiveYearAvgDividendYield`, the contribution is `currentValue × fiveYearAvgDividendYield / 100`. Results are summed in the preferred currency.

**Return type — `DividendEstimate`:**

| Field | Type | Description |
|---|---|---|
| `total` | `Decimal` | Sum of estimated annual income across covered stocks, in preferred currency |
| `coveredStocks` | `int` | Number of stocks with cached analyst data contributing to the estimate |
| `totalStocks` | `int` | Total number of held stocks (shares > 0) |
| `currency` | `String` | Preferred display currency |

**UI usage:** Shown on the Dividends screen Received tab as "Est. annual income ~€X" with a coverage note "(based on N of M stocks)" so the user understands the estimate is partial when analyst data is missing for some positions.

### 5.18 Self-Signed Certificate Support
The Nextcloud HTTP client (Dio) is configured with a custom `HttpClient` that supports self-signed certificates via explicit certificate pinning:
1. On first connection to a new server URL, the app fetches the server's certificate and presents its fingerprint (SHA-256) to the user for manual confirmation.
2. On confirmation, `SettingsActions.saveCertFingerprint()` persists the fingerprint to the `settings` table via `SettingsDao.updateCertFingerprint()`.
3. All subsequent WebDAV requests read the fingerprint from `AppSettings.nextcloudCertFingerprint` and pass it as the `pinnedFingerprint` named parameter to each `NextcloudService` method.
4. The certificate can be re-pinned by pressing "Test connection" on the Nextcloud settings screen.

`NextcloudService` is a stateless value class (`const NextcloudService()`). It does not manage fingerprint persistence; all WebDAV methods accept an optional `String? pinnedFingerprint` parameter and callers are responsible for supplying the correct value.

This approach avoids globally disabling TLS verification — only the explicitly approved certificate is trusted.

### 5.19 Debug Log Service and LogsScreen

`LogService` (in `core/services/log_service.dart`) writes timestamped log entries to a session-scoped flat text file (`stockmanager_debug.log`) in `getApplicationDocumentsDirectory()`. The file is truncated on each app launch so it never grows unbounded. Log entries are written via `IOSink` (serialised, no interleaving).

**Key API:**
| Method | Description |
|---|---|
| `LogService.create()` | Async factory: initialises the file and sink |
| `log(String? message)` | Appends `[ISO8601] message\n` to the sink |
| `filePath` | Absolute path to the log file |
| `readRecent({int lines = 300})` | Flushes the sink, reads the file, returns the last N lines |
| `clear()` | Flushes and closes the sink, reopens for writing, writes a fresh session header |

`LogsScreen` (at `/settings/about/logs`) is a `ConsumerStatefulWidget` that:
- Loads lines on `initState()` via `readRecent(lines: 300)`.
- Renders them in a scrollable `ListView.builder` with monospace 11 sp text.
- Colour-codes lines: `[ERROR]` → `colorScheme.error`, `[WARN ]` → `colorScheme.tertiary`, others → `onSurface`.
- Provides two app-bar actions: **Export** (shares the log file via `SharePlus.instance.share`) and **Clear** (confirmation dialog → `LogService.clear()` → reload).

### 5.20 AI Portfolio Analysis

`AnalysisScreen` (`/settings/ai-analysis`) provides a conversational portfolio analysis feature backed by a user-selectable LLM provider.

**Provider abstraction:** `LlmService` (in `core/services/llm_service.dart`) is an abstract interface with a single method `Stream<String> streamAnalysis(...)`. Three concrete implementations handle SSE streaming:
- `ClaudeService` — `POST api.anthropic.com/v1/messages` with `x-api-key` and `anthropic-version: 2023-06-01` headers; uses `cache_control: {type: ephemeral}` on the system prompt block for prompt caching.
- `GroqService` — OpenAI-compatible endpoint at `api.groq.com/openai/v1/chat/completions`; Bearer token auth; parses `choices[0].delta.content`.
- `GeminiService` — `generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse&key={apiKey}`; parses `candidates[0].content.parts[0].text`.

All three use `Dio` with `ResponseType.stream` and a shared line-buffer SSE parser pattern.

**Active provider selection:** `AnalysisNotifier.analyse()` reads the active provider, model, and API key directly from the Drift DAO on each invocation — not from cached Riverpod providers — to always use the latest settings without stale-cache issues.

**Portfolio serialisation:** `_serialisePortfolio()` converts `PortfolioSummary` to JSON via `jsonEncode`. Includes per-position fields (ticker, shares, avg buy price, current value, P&L) and portfolio-level totals. Sent as the user message payload alongside the query.

**ISIN suggestions:** The system prompt instructs the LLM to optionally append a `---STOCK_SUGGESTIONS---` delimiter followed by a JSON array of `{isin, name, reason}` objects. `_parseSuggestions()` splits on this delimiter after streaming completes, decodes the JSON, and exposes suggestions as `List<StockSuggestion>`. Each suggestion is displayed with an "Add" button that routes to `/stocks/add` with the ISIN pre-filled via `state.extra`.

**Buy recommendations panel:** In the `idle` state, a `_TopBuysSection` card is rendered above the prompt chips. It watches `portfolioSummaryProvider` and, for each currently-held position, reads the `analystDataProvider` keepAlive cache. Positions where `recommendationKey` is `buy` or `strong_buy` are collected, sorted (strong_buy first, then by descending upside-to-analyst-target), and shown as compact `ListTile` rows with a coloured recommendation badge, analyst count, and upside percentage. Tapping a tile navigates to the stock detail screen. The section is invisible when no cached buy/strong_buy data is available yet.

**State machine:** `AnalysisState` cycles through `idle → loading → streaming → done | error`. The UI shows the buy recommendations panel and predefined prompt chips in the idle state, a spinner during loading, a streaming `MarkdownBody` during streaming (auto-scrolls via `ScrollController`), and the completed response plus optional suggestion chips when done.

**Settings screen (`AiAnalysisSettingsScreen`):** Provider radio buttons, a single `TextEditingController` for the API key (reloaded when the provider changes), and a model radio group that updates via `modelsFor(activeProvider)`. Settings are read via a `Future` cached in `_settingsFuture` (initialised in `initState`, refreshed after each write) to avoid showing a loading flash on every `setState`.

### 5.21 Broker Import

`BrokerImportScreen` (`/settings/broker-import`) lists supported brokers. Flatex is currently **available**; DEGIRO, Interactive Brokers, Trade Republic, Scalable Capital, and Comdirect remain `comingSoon`. Tapping a live broker tile navigates to its dedicated import screen.

**Extension point:** To enable a new broker, set its status to `BrokerImportStatus.available` in the `_brokers` const list in `broker_import_screen.dart` and add a navigation case in `_onImport()`.

### 5.22 Flatex CSV Import

`FlatexImportScreen` (`/settings/broker-import/flatex`) drives a three-phase flow: **idle → previewing → importing → done**.

#### Parser (`FlatexOrderParser`)

Parses the semicolon-delimited, Latin-1-encoded "Orders" CSV exported from the Flatex web portal. Column indices are constants; all price strings use German decimal notation (`1.000,50`).

**Row types handled:**

| Row type | Source columns | Result |
|---|---|---|
| Regular limit / stop-market orders | col 12 (Limit) + col 13 (currency) | `FlatexParsedOrder` — direct import |
| KVG savings-plan / Bruchstücke (Stück-unit) | col 10 (Ausführungspreis) + col 11 (currency) | `FlatexParsedOrder` — direct import |
| EUR-unit rows with execution price | menge ÷ price | `FlatexParsedOrder` — shares derived |
| EUR-unit rows **without** execution price (KVG market) | invested EUR amount only | `FlatexUnpricedOrder` — offered for estimation |
| Stück-unit with no price anywhere | — | `skippedNoPrice` |
| Non-executed orders | — | `skippedNotExecuted` |
| Empty-unit rows | — | `skippedFractional` |
| Bad ISIN, bad date, zero menge | — | `skippedOther` |

**Col 11 guard:** Flatex sometimes puts the order-type keyword (`"Limit"`, `"Market"`, `"Stop"`) in col 11 (Ausführungswährung) instead of a currency code. `_isCurrencyCode()` accepts only exactly-3-uppercase-ASCII-letter strings, so keywords are silently rejected and the currency defaults to `'EUR'`.

**`FlatexParseResult`** exposes `importable`, `unpricedOrders`, and four skip counters. Its `total` getter sums all categories, including unpriced orders, so a CSV containing only unpriced rows is not incorrectly treated as empty.

#### Price estimation for unpriced orders

When `FlatexParseResult.unpricedOrders` is non-empty, the previewing screen shows a `SwitchListTile`. Enabling it calls `_fetchEstimatedPrices()`:

1. For each `FlatexUnpricedOrder`, look up the stock's ticker symbol:
   - If the ISIN already exists in the database (`StocksDao.findByIsin()`), use the stored symbol — avoids an extra OpenFIGI round-trip.
   - Otherwise call `IsinLookupService.lookup(isin)` (OpenFIGI API).
2. Call `MarketDataService.fetchHistoricalPrice(symbol, executedAt)` for the closing price on the order date.
3. If the security's native currency is not EUR, convert to EUR using ECB rates (`CurrencyService.fetchRates('EUR')` — fetched once for the batch via lazy `??=`). `ExchangeRate.find(rates, nativeCcy, 'EUR').convert(price)`.
4. Derive share count: `shares = investedAmount ÷ priceInEur`.
5. Add a `FlatexParsedOrder` with `isEstimated: true`.

Orders that fail (symbol not found, no historical price, no exchange rate) are listed by name in a warning card. The Import button is disabled while estimation is in progress to prevent importing partial results.

#### Import phase

`_import()` merges `result.importable` and `_estimatedOrders`, groups by ISIN, then for each ISIN:
- Finds or creates the stock (new stocks get their symbol/currency from OpenFIGI; currency falls back to the CSV execution currency to keep transaction and stock currency consistent).
- Deduplicates by `externalRef` (order number) when non-empty; falls back to exact-match on `(stockId, executedAt, isBuy, shares)`.
- Sets `notes = "Price estimated from historic closing price"` on estimated transactions so `TransactionTile` can display a visual review badge (orange warning icon + subtitle line).

#### Visual review badge

`TransactionTile` checks `transaction.notes?.contains('estimated')`. When true:
- The leading avatar shows an amber warning icon instead of B/S.
- The tile turns amber (`Colors.orange.shade700`) instead of green/red.
- A second subtitle line reads "⚠ Price estimated — please verify".
- `isThreeLine: true` is set on `ListTile` to accommodate the extra line.

### 5.23 Portfolio History Chart


`PortfolioHistoryChart` is a `ConsumerWidget` rendered below the `PortfolioSummaryCard` on the Dashboard. It visualises the evolution of the portfolio across calendar years using a **stacked area chart** plus a **dividends sub-chart**.

#### Data provider — `portfolioHistoryProvider`

A `FutureProvider<List<PortfolioHistoryPoint>>` that:

1. Collects all stocks and their transactions, splits, and dividends.
2. Fetches `ChartRange.max` (monthly granularity) price history for every stock via `priceHistoryProvider` — the same keepAlive cache used by the stock detail chart, so no extra API calls when both are open.
3. Iterates from the earliest transaction year to the current year. For each year:
   - Computes `investedCapital` (cost basis of open positions) and `realisedPnl` (cumulative) from `PortfolioCalculator` and `PnlCalculator`.
   - Computes `dividends` (cumulative confirmed paid dividends) from the dividends list.
   - For the **current year** computes `totalValue` from live quotes in `priceQuotesProvider`.
   - For **past years** finds the last price point at or before Dec 31 in the fetched history and computes `totalValue` from `sharesHeld × adjustedPrice`. When no price point exists for a year the `totalValue` is `null` for that year.
4. Skips years with no activity (all three aggregate values are zero).

**`PortfolioHistoryPoint`** model:

| Field | Type | Description |
|---|---|---|
| `year` | `int` | Calendar year |
| `investedCapital` | `Decimal` | Cost basis of open positions at year-end |
| `realisedPnl` | `Decimal` | Cumulative realised P&L up to year-end |
| `dividends` | `Decimal` | Cumulative confirmed net dividends up to year-end |
| `totalValue` | `Decimal?` | Portfolio market value at year-end; null when no price history is available |
| `currency` | `String` | Preferred display currency |
| `isProjected` | `bool` | True for extrapolated future data points |

#### Main chart (stacked area)

Uses `fl_chart LineChart` with three series rendered in back-to-front order (later series paints on top of earlier ones, producing correct coloured zones without per-point clipping):

| Series | Fill area | Colour |
|---|---|---|
| 0 — Total (investedCapital + unrealised) | from total down | `Color(0xFF4C7CE5)` (blue) + `Color(0xFF2DB87D)` (teal) combined |
| 1 — Invested + realised | from series 1 down | `Color(0xFF1A8A57)` (dark green) |
| 2 — Invested capital | from series 2 down | `Color(0xFF4C7CE5)` (blue) |

`isCurved: false` prevents artifacts when data spans only a few years. A single tooltip (anchored to `barIndex == 0`) shows Invested / Unrealised / Realised / Total for the touched year.

#### Dividends sub-chart

A separate 90 dp tall `fl_chart BarChart` below the main chart, showing cumulative dividends per year in amber (`Color(0xFFE5A23C)`). It shares the same X-axis domain (years) as the main chart.

#### Forecast

When `portfolioHistoryProvider` returns at least two data points, `_forecast()` appends two extrapolated future years using linear slope projection:

- `sInvested` = slope of `investedCapital` (first → last point)
- `sPnl` = slope of `realisedPnl`
- `sDivs` = slope of `dividends`
- `sUnrealised` = slope of `_unrealisedFor(p)` where `_unrealisedFor(p)` is `p.totalValue != null ? p.totalValue! − p.investedCapital : Decimal.zero`

Projected `totalValue = clampedInvested + projUnrealised` (both clamped to zero). Forecast points have `isProjected: true` and are rendered with dashed lines.

### 5.24 Startup Crash Diagnostics

`main.dart` maintains a lightweight crash-log file at `<documents>/stockmanager_crash.txt`. All writes are **synchronous** (`File.writeAsStringSync(flush: true)`) so they survive a hard process kill (SIGKILL, OOM kill) that would leave async writes incomplete.

**Lifecycle:**
1. `_initCrashLogPath()` is awaited first in `_mainWithDiag()` before any other startup step.
2. If a log file from the previous session exists at startup, `_CrashReportApp` is shown full-screen before the main app launches. The user can screenshot the log and tap "Clear and launch app" to continue.
3. `_main()` appends numbered step markers (`[1]`–`[14]`) as startup proceeds through each major phase (WidgetsFlutterBinding, LogService, WorkManager, AppDatabase, NotificationService, services, runApp, postFrameCallback, permission request).
4. The `runZonedGuarded` error handler calls the synchronous `_appendCrashLog('CRASH: $error\n$stack')` before `debugPrint`, so the last exception is flushed to disk even if the next write in the same zone kills the process.
5. The log is cleared 15 seconds after the first frame (3 s + 7 s + 5 s in three checkpoints) to allow async provider/DB work to settle. Clearing too early would remove the diagnostic before a post-frame provider crash is recorded.

**Known gap:** Crashes that occur before `_initCrashLogPath()` completes (i.e. during `WidgetsFlutterBinding.ensureInitialized()` or within the `getApplicationDocumentsDirectory()` call itself) hit the zone error handler when `_crashLogPath` is still null. `_appendCrashLog` silently no-ops in that case; the crash is printed to logcat via `debugPrint` but does not appear in the diagnostic screen on the next launch. Very-early startup failures must still be diagnosed via ADB.

**Crash-report screen (`_CrashReportApp`):** A minimal `MaterialApp` (deep-orange theme) that renders the crash log in a `SelectableText` on a black background. It does not use `ProviderScope` or any production infrastructure — it must be renderable even when the database or plugins are broken.

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
/settings/ai-analysis    → AI Portfolio Analysis (AnalysisScreen)
/settings/ai-analysis/key → Provider / API key / model picker (AiAnalysisSettingsScreen)
/settings/broker-import         → Import from Broker (broker picker)
/settings/broker-import/flatex  → FlatexImportScreen (CSV parse → preview → import)
/settings/backup         → Local backup (export / import ZIP)
/settings/market-data    → MarketDataSettingsScreen
/settings/nextcloud      → Nextcloud configuration
/settings/currency       → Currency preferences & overrides
/settings/notifications  → Notification preferences
/settings/about          → App version, GPL-3 licence, privacy policy, app logs
/settings/about/privacy-policy  → In-app privacy policy (offline)
/settings/about/logs     → LogsScreen: scrollable log viewer, share/clear
```

All routes are nested inside the `ShellRoute` so the navigation chrome (sidebar / bottom bar) is always present.

---

## 7. Testing

### 7.1 Test layout

```
test/
├── widget_test.dart                    # App smoke test (dashboard renders)
├── manual_price_dialog_test.dart       # ManualPriceDialog widget tests
├── calculators/
│   ├── portfolio_calculator_test.dart  # PortfolioCalculator — all public methods
│   ├── pnl_calculator_test.dart        # PnlCalculator — unrealised/realised P&L
│   └── dividend_calculator_test.dart   # DividendCalculator + Dividend.netAmount
├── utils/
│   └── decimal_math_test.dart          # DecimalX extensions + DecimalMath
├── models/
│   └── exchange_rate_test.dart         # ExchangeRate.find / convert / isStale
├── database/
│   └── trailing_stop_test.dart         # StocksDao trailing stop DAO methods
└── parsers/
    └── flatex_order_parser_test.dart   # FlatexOrderParser — all row types, skip counters, real-world format
```

### 7.2 Testing strategy

**Pure domain logic** (`calculators/`, `models/`, `utils/`) — plain Dart unit tests using `flutter_test`. No Flutter framework, no I/O. Each test is self-contained and deterministic.

**Database integration** (`database/`) — use `AppDatabase.forTesting(NativeDatabase.memory())` to run real Drift queries against an in-memory SQLite database. Each test gets a fresh schema via `setUp`/`tearDown`. FK constraints are enforced: a broker must be inserted before a stock.

**Widget tests** — use `ProviderScope` with overrides for all infrastructure providers (`databaseProvider`, `marketDataServiceProvider`, etc.). `portfolioSummaryProvider` is overridden with a static value to prevent Drift's `StreamQueryStore` from leaking `Timer` instances into the `FakeAsync` zone. In-memory DBs are closed via `tester.runAsync(db.close)`.

### 7.3 What is not tested

- Individual screen widgets beyond the dashboard smoke test — acceptable for a portfolio app where the domain logic (tested) drives correctness; UI structure is verified by the build CI jobs.
- `BackgroundCheckService` — runs in a WorkManager isolate and has no seams for unit injection without a full Android integration test harness.
- `MarketDataService` / `CurrencyService` — HTTP services; covered by manual testing against live APIs and by `_NoOpMarketDataService` in widget tests.
