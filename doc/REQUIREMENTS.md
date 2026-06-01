# StockManager — Requirements

## 1. Overview

StockManager is a cross-platform portfolio tracking application for managing stocks held across multiple brokers. It provides real-time valuations, tracks buy/sell transactions and dividends, and synchronises all data with a Nextcloud instance in a spreadsheet format.

---

## 2. Brokers

- The app supports **up to 10 brokers**.
- Brokers can be added, edited, and removed within the app.
- Each broker has at minimum: name, optional notes/description.

---

## 3. Stocks

- Up to **100 different stocks** can be managed across all brokers.
- Each stock is associated with one broker.
- Each stock is identified by its **ISIN** (International Securities Identification Number).
- The stock name, ticker symbol, exchange, and currency are **automatically resolved** from the ISIN via a lookup service when adding a stock; the user does not need to enter these manually.
- Resolved fields can be reviewed and corrected by the user before saving.
- On the Edit Stock screen, a **Research** button re-runs the ISIN lookup at any time, allowing the user to update the symbol, name, exchange, and currency in one step (e.g. after a ticker change or delisting migration).
- Stocks can be held in **different currencies**.
- Stocks can be added and removed in the app.

### 3.1 Transactions

- For each stock, the user can record **executed buy and sell transactions**.
- Each transaction records at minimum:
  - Transaction type (buy / sell)
  - Date and time of execution
  - Number of shares / units
  - Price per share at execution
  - Currency
  - Optional: fees/commission, notes

### 3.2 Stock Splits

- The user can record **stock splits and reverse splits** for any stock, including:
  - Date of the split
  - Split ratio (e.g. 4:1 or 1:10)
- All historical transaction prices and share counts are automatically adjusted to reflect splits, keeping the cost-basis accurate.

### 3.3 Average Position Price

- The app automatically calculates the **weighted average buy price** per stock from all recorded transactions.
- This is updated in real-time as new buy/sell transactions are added.

### 3.4 Realised and Unrealised P&L

- **Unrealised P&L**: difference between current market value and cost-basis for open positions.
- **Realised P&L**: profit or loss locked in from completed sell transactions.
- Both are shown per stock and as a portfolio total, in the preferred display currency.

---

## 4. Portfolio Overview

### 4.1 Total Portfolio Value

- Display the **total current value** of the entire portfolio.
- Aggregate values across all brokers and all currencies (with currency conversion).

### 4.2 Individual Stock Value

- Display the **current value per stock** (units × live price).
- Show the currency of each stock.

### 4.3 Live Market Data

- Current prices are fetched in **real-time from the Internet** (e.g. via a public market data API).
- Live data is used solely for display; the app functions without it (see Section 7).
- For securities not covered by any market data source, the user can set a **manual price override** directly from the stock detail screen. Manual prices are stored locally, never expire, and take precedence over live quotes. They can be cleared at any time to resume live data fetching.

### 4.4 Buy Price Overview

- Display the **total invested amount** across the portfolio.
- Display the **invested amount per stock** (sum of buy transactions minus sell proceeds).

### 4.5 Preferred Display Currency

- The user can select a **preferred display currency** in the app settings.
- The dashboard and all portfolio totals convert and display every value in this single currency using live (or last-known) exchange rates.
- Individual stock views still show the stock's native currency alongside the converted value.
- The user can set a **manual exchange rate override** per currency pair for use when offline or when the live rate is considered unreliable.

### 4.6 Dividends

- For each stock the user can record **paid-out dividends**, including:
  - Payment date
  - Amount per share
  - Total amount received
  - Currency
  - Optional: withholding tax, notes
- The app displays **expected (upcoming) dividends** per stock, including:
  - Expected payment date
  - Estimated total based on current holdings
- A dividend overview shows:
  - Total dividends received (all-time and per year), converted to the preferred display currency
  - Upcoming expected dividends with dates and estimated totals
  - **Estimated annual income** — derived from Yahoo Finance's 5-year average dividend yield × current position value for each stock; shown on the dividend overview as a portfolio-wide estimate with a coverage note (how many stocks have cached analyst data)
- Each stock has an optional **Dividend Reinvestment (DRIP)** flag; when enabled, recorded dividend payments automatically generate a corresponding buy transaction for that stock.
- Each stock displays its **annual dividend yield** (annual dividend per share ÷ current price × 100).
- The stock detail **Analysis card** includes a Dividends subsection showing Yahoo Finance data: **annual rate** (`trailingAnnualDividendRate`, hidden when zero/null), **5-year average yield** (`fiveYearAvgDividendYield`, already a percentage), and **estimated annual income** (shares held × current price × 5Y avg yield ÷ 100, in the stock's currency; shown only when shares are held).

---

## 5. Data Synchronisation — Nextcloud

- All portfolio data is **synchronised with a user-configured Nextcloud instance**.
- Synchronisation is triggered automatically (on startup and after data changes, debounced 5 s) and manually ("Backup now").
- The app supports Nextcloud instances that use **self-signed TLS certificates**; the user can explicitly accept and pin a server certificate during initial setup.
- The sync backup format is a **ZIP archive** containing JSON files (`brokers.json`, `stocks.json`, `transactions.json`, `dividends.json`, `stock_splits.json`, `meta.json`). The ZIP is the sync source-of-truth; it is readable but not intended for direct editing.
- A separate **ODS (OpenDocument Spreadsheet)** export is available from the local backup screen for human-readable archival; it can be opened in LibreOffice Calc, OnlyOffice, or any ODS-compatible suite and contains all brokers, stocks, transactions, dividends, and current valuations.
- Both export formats snapshot all five tables atomically inside a single database transaction to guarantee consistency.
- Each backup filename includes a full UTC timestamp (`stockmanager_backup_YYYY-MM-DDTHH-MM-SSZ.zip`) so the most recent file is unambiguous. Up to N previous backups are retained on the server (N configurable in Settings, default 5); older files are deleted automatically.
- **Conflict resolution:** at startup (and after a credential save), the app compares the remote backup timestamp against `lastSyncAt`. If the remote backup is newer, the user is offered a proactive "Restore from server?" dialog. Auto-upload is suppressed while a restore decision is pending.
- When a restore is performed, `importFromBytes()` returns the count of child rows (transactions, dividends, splits) skipped because their parent stock was absent from the backup file. If any rows were skipped the UI surfaces a visible warning (e.g. "3 row(s) were skipped due to missing stock references") so no data is silently lost.
- **Nextcloud is optional** — the app is fully functional without it; sync can be enabled or disabled at any time.

---

## 6. Supported Platforms

| Platform | Minimum Version |
|---|---|
| Android | Android 13 |
| macOS | macOS 15 |
| Ubuntu | Ubuntu 24.04 |
| Windows | Windows 11 |

- The Android build is a native mobile application.
- The PC builds (macOS, Ubuntu, Windows) share a common desktop codebase.

---

## 7. Offline Support

- The app **must be fully functional without an Internet connection**, with the following exceptions:
  - Live market prices require an active Internet connection; when offline, the last known prices (with a timestamp) are displayed instead.
  - Nextcloud synchronisation requires an active network connection to the Nextcloud server.
- All portfolio data (brokers, stocks, transactions, historical prices) is stored **locally on the device**.

---

## 8. Notifications and Alerts

- The app sends **local notifications** (no external server required) on all platforms for:
  - An approaching expected dividend payment date (configurable lead time, e.g. 3 days before)
  - A stock price rising or falling by a user-defined percentage threshold
  - A **trailing stop-loss** alert per stock: a configurable drop-from-peak threshold (e.g. −10%). The peak price is tracked automatically; a notification fires when the price falls to or below peak × (1 − threshold). The high-water mark resets after the alert fires so it does not re-trigger until a new peak is reached.
  - An analyst consensus rating changing for a held stock
- On Android, notifications are delivered via **WorkManager** background tasks (periodic checks every 15 minutes when a network connection is available); no Firebase / FCM dependency.
- On desktop (macOS, Windows, Ubuntu), local notifications are sent directly by the running app.
- Notifications are optional and configurable in Settings.

---

## 9. Non-Functional Requirements

- **Privacy**: all data remains on the user's own device and their own Nextcloud; no third-party cloud storage. A full privacy policy is displayed in-app (Settings → About → Privacy policy), covering all third-party services contacted and the data sent to each.
- **Responsive / adaptive UI**: the app uses a single adaptive layout that adjusts to screen size:
  - **Android**: single-column navigation, bottom navigation bar, touch-optimised controls.
  - **Desktop** (macOS, Windows, Ubuntu): multi-column layout making use of the available screen space — e.g. a persistent sidebar for navigation, a master-detail split for stock lists and detail views, and wider dashboard panels showing more data at once without scrolling.
- **Dark mode**: the app supports light and dark themes on all platforms, following the system preference by default.
- **Performance**: the app must load the portfolio overview within 2 seconds on a modern device (offline data only).
- **Data integrity**: transactions and portfolio data must not be lost during sync or app updates.
- **Crash diagnostics**: the Android release build maintains a startup crash log that survives a hard process kill. If the previous session ended unexpectedly, the crash log is shown on-screen before the next launch so the user can screenshot it without needing ADB or a file manager.
- **Automated testing**: all domain logic (portfolio calculations, P&L, dividends, currency conversion, decimal math) is covered by unit tests that run in CI on every push. The test suite must pass with zero failures before any build job runs.

---

## 10. Planned Features

Features confirmed for a future version. Not in scope for the initial release.

### 10.1 Analyst Target Price and Rating ✓ *(delivered)*
- Each stock detail view displays the **consensus analyst target price** (fetched from Yahoo Finance) alongside the current price.
- The **analyst consensus rating** (Strong Buy / Buy / Hold / Underperform / Sell) is shown as a coloured chip, including the number of analysts contributing to the consensus.
- The target price range (low / mean / high) is shown as a gradient range bar with the current price marked.
- Upside / downside percentage relative to the current price is shown next to the mean target, colour-coded green (upside) or red (downside).
- A **consensus breakdown bar** shows the proportion of Strong Buy / Buy / Hold / Sell / Strong Sell ratings visually.
- **52-week high/low** range bar is shown on the same card.
- **Valuation metrics** — trailing P/E, forward P/E, EPS (TTM), EV/EBITDA, P/B ratio, PEG ratio, and FCF yield — are shown when available, in the stock's trading currency.
- All analyst prices are converted from the stock's trading currency to the stock's base currency for display; currency conversion uses the same exchange rate mechanism as portfolio values.
- A **refresh button** on the analysis card allows the user to force a re-fetch at any time.
- Data is cached for 10 minutes per stock (no network round-trip on quick navigation away and back).

### 10.2 Configurable Market Data Provider ✓ *(delivered)*
- The user can choose the **market data provider** for analyst consensus data in Settings → Market Data.
- Supported providers:
  - **Yahoo Finance** (default) — no account or API key required; unofficial API, subject to rate-limiting.
  - **Finnhub** (optional) — requires a free Finnhub API key entered by the user; provides more reliable and structured analyst data (price targets, consensus ratings, EPS estimates).
- The API key for Finnhub is stored in the settings table alongside other Nextcloud credentials.
- Switching providers invalidates any cached analyst data so the next screen open re-fetches from the new source.
- When Finnhub is the active provider, any fields it does not supply (e.g. `fiveYearAvgDividendYield`, `trailingAnnualDividendRate` for non-US stocks) are supplemented from a parallel Yahoo Finance request, so dividend data is always shown when available.
- When Finnhub is selected but no API key is configured, the Analysis card shows an 'API key required' prompt with a tap-through link to Settings → Market Data.
- A link to the Finnhub free registration page is shown next to the API key field.

### 10.3 Trailing Stop-Loss Notification ✓ *(delivered)*
- The user can set a **trailing stop-loss threshold** per stock (e.g. −10%).
- The threshold tracks the stock's highest recorded price since the alert was enabled.
- A notification is triggered when the current price falls more than the threshold percentage below that peak.
- The trailing high-water mark is updated automatically as the price rises.
- Configurable per stock; displayed alongside the current price on the stock detail screen.

### 10.4 Watchlist (Monitoring-Only Stocks) ✓ *(delivered — via zero-transaction stocks)*
- Stocks can be added in **monitoring mode** — no broker assignment, no transactions required.
- Watchlist stocks appear in a dedicated section separate from held positions.
- All live price, target price, rating, and news features apply to watchlist stocks.
- A watchlist stock can be promoted to a held position at any time by assigning a broker and adding a transaction.
- *Implementation note:* a stock with no transactions naturally shows zero shares held and no P&L. The existing Add Stock flow covers this without a separate watchlist concept.

### 10.5 Price History Chart ✓ *(delivered)*
- Each stock detail view includes a **price history chart** showing closing prices over selectable time ranges: 1D · 1W · 1M · 6M · 1Y · 5Y · MAX.
- The selected range label is highlighted; switching ranges triggers a fresh fetch.
- The line is green for a positive period change, red for negative; the area below the line is filled with a matching gradient.
- The period percentage change (e.g. +1.57%) is shown next to the card title.
- Touching the chart shows a tooltip with the exact price and date.
- Data is fetched from Yahoo Finance at an appropriate interval for each range (e.g. 5-minute bars for 1D, daily for 1M, weekly for 1Y).
- Buy and sell transactions within the visible date range are shown as coloured dots on the price line; touching near a dot shows the transaction type, share count, and price.
- Mini sparklines are shown on the dashboard stock list for a configurable time range (default: 1M).

### 10.6 Stock News ✓ *(delivered)*
- Each stock detail view includes a **news feed** of recent articles related to that stock.
- News is fetched from Finnhub company-news (when an API key is configured) with a fallback to Yahoo Finance search.
- Articles open in the device's default browser.
- News requires an Internet connection; a “no connection” placeholder is shown offline.

### 10.7 Broker Import / Export ✓ *(Flatex delivered; others planned)*

**Flatex (delivered):** The app imports transaction history from the semicolon-delimited "Orders" CSV exported by the Flatex web portal. Supported row types: regular limit/stop orders, KVG savings-plan (Ausführungspreis column), Bruchstücke (fractional units), and EUR-unit KVG market orders (share count estimated from a historic closing price via Yahoo Finance). Unpriced rows are shown in a preview step with an optional "estimate prices" toggle; import is disabled until estimation completes. All rows are deduplicated by broker order number (`external_ref`) on re-import. New stocks are auto-resolved via OpenFIGI (ISIN → symbol/currency) and created automatically.

**Planned for other brokers:** DEGIRO, Trade Republic, Scalable Capital, Comdirect, Interactive Brokers. Each broker needs a named import profile mapping its CSV/XLSX columns to the app's data model. Unrecognised rows are flagged for manual review before import is confirmed.

### 10.9 Dashboard Closed-Position Filter ✓ *(delivered)*
- The dashboard Holdings list includes a **toggle button** in the AppBar to hide positions where the user currently holds zero shares (fully sold / closed positions).
- When the filter is active, a count of hidden closed positions is shown next to the "Holdings" section header (e.g. "(3 closed hidden)").
- When all visible positions are closed and the filter is active, an "All positions are closed." placeholder replaces the empty list.
- The filter state is local to the session (not persisted); it defaults to showing all positions.
- The portfolio summary card and allocation chart are unaffected by the filter — they always reflect the full portfolio.

### 10.8 AI Portfolio Analysis ✓ *(delivered — Claude, Groq, Gemini)*
- The user can request an **AI-powered analysis of their portfolio** via the Claude API (Anthropic).
- The feature requires the user to supply their own **Anthropic API key**, stored in the settings table (same pattern as the Finnhub key).
- On request, the app serialises all portfolio data (stocks, transactions, dividends, current valuations) to a structured JSON payload and sends it to the Claude API.
- The response is displayed in a dedicated **Analysis screen** as streamed text.
- Example analyses the user can request:
  - Portfolio concentration and diversification
  - Sector / geographic exposure breakdown
  - P&L trend and performance attribution
  - Dividend income projection
  - Risk commentary (volatility, single-stock weight)
  - Natural-language Q&A over the user's own data
- A **privacy notice** is shown before the first request, clearly stating that portfolio data is transmitted to Anthropic's servers.
- The user can opt out at any time by removing the API key; no data is ever sent automatically.
- API calls are always user-triggered (no background analysis).

**Delivered implementation:**
- Three providers are supported: **Anthropic Claude** (`claude-opus-4-7` default), **Groq** (`llama-3.3-70b-versatile` default, free tier), and **Google Gemini** (`gemini-2.0-flash` default, free tier).
- The active provider, model, and API key are selected in Settings → AI Analysis.
- All providers stream their responses via SSE; the response is rendered as Markdown in real-time.
- The LLM is instructed to append `---STOCK_SUGGESTIONS---` followed by a JSON array of `{isin, name, reason}` objects. Suggestions are displayed as "Add stock" chips below the response; tapping one opens the Add Stock screen pre-filled with the ISIN.
- Prompt caching (`cache_control: ephemeral`) is applied to the system prompt block when using Claude, reducing cost on repeated queries.
- In the idle state (before any analysis is run), the Analysis screen displays a **Top Buy Recommendations** panel listing currently held stocks that have a `buy` or `strong_buy` analyst consensus rating. Stocks are sorted with `strong_buy` first, then by upside-to-target descending. Each entry shows the stock name, coloured recommendation badge, number of contributing analysts, and upside percentage to the mean target price. Only stocks with cached analyst data are shown; the panel is hidden if there are no qualifying holdings.

