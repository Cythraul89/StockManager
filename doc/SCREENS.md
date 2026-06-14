# StockManager — Screen Designs

All screens exist in two layout variants selected automatically by the adaptive shell:
- **Mobile** (< 600 dp): single column, bottom navigation bar with 5 tabs.
- **Desktop** (≥ 600 dp): persistent left sidebar (240 dp) + content area; master-detail split where noted.

---

## Navigation Structure

**Mobile — bottom bar tabs**
```
[ Dashboard ]  [ Stocks ]  [ Dividends ]  [ Analysis ]  [ Settings ]
```

**Desktop — left sidebar**
```
┌────────────────────┐
│  StockManager      │
│  ───────────────── │
│  Dashboard         │
│  Stocks            │
│  Dividends         │
│  Analysis          │
│  Settings          │
└────────────────────┘
```

The `Brokers` section is accessible via **Settings → Portfolio → Brokers** (`/settings/brokers`), not as a top-level nav item. The `/analysis` tab shows the Portfolio Analysis screen (history chart + buy recommendations).

---

## 1. Dashboard

**Purpose:** At-a-glance portfolio health — total value, P&L, allocation, portfolio history, holdings.

### Mobile
```
┌─────────────────────────────┐
│  Dashboard        [👁] [↺]  │  ← visibility toggle · refresh
│                             │
│  Portfolio Value            │
│  € 24,830.12        ▲ +1.4% │
│                             │
│  ┌──────────┐ ┌──────────┐  │
│  │Invested  │ │Realised  │  │
│  │€ 18,400  │ │P&L +€320 │  │
│  └──────────┘ └──────────┘  │
│                             │
│  ┌──────────┐ ┌──────────┐  │
│  │Unrealised│ │Dividends │  │
│  │+€ 6,430  │ │YTD €420  │  │
│  └──────────┘ └──────────┘  │
│                             │
│  Allocation                 │  ← AllocationChart card
│  ┌─────────────────────────┐│
│  │ (●) ●  ● AAPL  45.2%   ││  ← donut + legend
│  │  ╲●╱    MSFT  30.1%    ││
│  │         VOW3  14.7%    ││
│  │         Others  10.0%  ││
│  └─────────────────────────┘│
│                             │
│  Portfolio History          │  ← PortfolioHistoryChart
│  ┌─────────────────────────┐│
│  │   ████████████████░░░░  ││  ← stacked area: invested (blue)
│  │   ░░░░░░░░░░░░░░░░░░░░  ││    + unrealised (teal on top)
│  │  2022  2023  2024  2025 ││    + realised (dark green on top)
│  │  Dividends sub-chart    ││  ← separate bar sub-chart (amber)
│  └─────────────────────────┘│
│                             │
│  Holdings  (3 closed hidden)│  ← suffix shown when filter is active
│  ┌─────────────────────────┐│
│  │ AAPL [Buy] ╭╮  +3.2% €189││  ← badge · sparkline · value
│  │ MSFT [Hold]╯╰  -1.1% €412││
│  │ VOW3 [Buy] ╭─  +0.8% € 92││
│  └─────────────────────────┘│
└─────────────────────────────┘
```

**Closed-position filter:** The eye icon in the AppBar toggles visibility of zero-share positions (fully sold stocks whose records still exist). When active, the icon changes to `visibility_off` and the Holdings header shows `(N closed hidden)`. The summary card and allocation chart are unaffected.

**Stock tiles:** Each tile in the stock list (dashboard and Stocks tab) shows:
- A small coloured recommendation badge (Str.Buy · Buy · Hold · Undprf. · Sell) next to the ticker symbol, loaded silently via `analystDataProvider` (10-minute keepAlive); hidden while loading or when unavailable.
- A 72×36 px **sparkline** (mini line chart) between the name column and the value column, showing price history for the configured period (default 1M). Green when the period end price ≥ start price, red otherwise. Hidden while loading or when fewer than two data points are available.

The sparkline period is configurable in Settings → Display → "Sparkline period" (1D · 1W · 1M · 6M · 1Y · 5Y · MAX). Changing it immediately updates all visible sparklines.

### Desktop (additions)
- Summary cards displayed in a 4-column row (no scrolling needed).
- Top Movers and Upcoming Dividends shown side-by-side in two columns.
- A mini portfolio allocation chart (by broker or by stock) shown as a third panel on the right.
- Live prices auto-refresh every 60 seconds with a visible countdown.

---

## 2. Stock List

**Purpose:** Browse and manage all stocks grouped by broker.

### Mobile
```
┌─────────────────────────────┐
│  Stocks             [+ Add] │
│  [ 🔍 Search…       ] [⋮↕] │  ← TextField + sort PopupMenuButton
│  ───────────────────────────  │
│  Broker: Scalable Capital   │
│  ┌─────────────────────────┐│
│  │ AAPL  Apple Inc.        ││
│  │ 10 shares · $ 189.40    ││
│  │ Value € 1,756  ▲ +12%   ││
│  ├─────────────────────────┤│
│  │ MSFT  Microsoft         ││
│  │  5 shares · $ 412.00    ││
│  │ Value € 1,920  ▲  +8%   ││
│  └─────────────────────────┘│
│                             │
│  Broker: Trade Republic     │
│  ┌─────────────────────────┐│
│  │ ALV   Allianz SE        ││
│  │ 20 shares · € 270.50    ││
│  │ Value € 5,410  ▲  +4%   ││
│  └─────────────────────────┘│
└─────────────────────────────┘
```

**Search and sort:** A `TextField` below the AppBar filters stocks live by symbol or name (case-insensitive). A `PopupMenuButton` in the AppBar offers three sort orders — **Symbol** (default, alphabetical), **Name** (alphabetical), and **Price** (descending by last known quote). When no stocks match the search query an inline "No results for '…'" message replaces the list. Sort by price is cross-currency (stocks with no quote sort last; JPY prices are not normalised to the preferred currency).

### Desktop (master-detail)
```
┌──────────────┬────────────────────────────────────────────┐
│  Stocks [+]  │  AAPL — Apple Inc.                       │
│  ──────────  │  (see Stock Detail, section 3)           │
│  ▾ Scalable  │                                          │
│    AAPL ●   │                                          │
│    MSFT      │                                          │
│  ▾ Trade Rep │                                          │
│    ALV       │                                          │
│    VOW3      │                                          │
└──────────────┴────────────────────────────────────────────┘
```
Selecting a stock in the left panel loads the detail in the right panel without navigating away.

---

## 3. Stock Detail

**Purpose:** Full view of one stock — price, position, P&L, analyst data, transactions, dividends.

### Mobile (scrollable)
```
┌─────────────────────────────┐
│  ← AAPL                [✏] │
│                             │
│  ┌─────────────────────────┐│
│  │ Apple Inc.              ││
│  │ NASDAQ · US0378331005   ││
│  │ ─────────────────────── ││
│  │ Shares held    10.000000││
│  │ Avg buy price   $ 145.20││
│  │ Invested        $ 1,452 ││
│  │ Current price   $ 189.40││  ← fetched on open if not in cache
│  │ Unrealised P&L  +$ 442  ││  ← coloured green / red
│  │ Realised P&L    +$  80  ││
│  │ Change [1D +0.8%][1W +2.1%][1Y +18.4%]││  ← coloured badges
│  └─────────────────────────┘│
│                             │
│  ┌─────────────────────────┐│  ← Price history chart
│  │ Price History  +2.3%  [USD][EUR]││  ← currency toggle pills
│  │ $195┤       ╭──╮         ││  ← Y-axis price labels
│  │ $190┤  ╭────╯  ╰──╮     ││
│  │ $185┤──╯           ╰────││
│  │      └──────────────────││
│  │ [1D][1W][1M][6M][1Y][5Y][MAX]││  ← range selector
│  └─────────────────────────┘│
│                             │
│  ┌─────────────────────────┐│  ← Analysis card
│  │ Analysis  14 analysts [↺]││  ← ↺ refresh button
│  │ ┌────────────────────┐  ││
│  │ │ Strong Buy         │  ││  ← coloured chip
│  │ └────────────────────┘  ││
│  │ Target price  $ 230 +21%││  ← mean ± % upside in colour
│  │ ▓░░░░░░░░│░░░░░░░░░░░░░ ││  ← range bar (low·current·high)
│  │ $ 180          $ 260    ││
│  │                         ││
│  │ 52-Week Range           ││
│  │ ▓░░░░░░░│░░░░░░░░░░░░░░ ││
│  │ $ 164          $ 201    ││
│  │                         ││
│  │ Consensus               ││
│  │ ████████▒▒▒░░░──        ││  ← proportional colour bar
│  │ 8 Str.Buy · 5 Buy · … ││
│  │                         ││
│  │ Valuation               ││
│  │ P/E (trailing)  28.4×   ││
│  │ P/E (forward)   24.1×   ││
│  │ EPS (TTM)       $ 6.73  ││
│  │ EV/EBITDA       18.2×   ││
│  │ P/B ratio        5.41×  ││
│  │ PEG ratio        2.34   ││
│  │ FCF yield        3.21%  ││
│  │                         ││
│  │ Dividends               ││
│  │ Annual rate     $ 1.00  ││  ← trailingAnnualDividendRate; hidden when zero/null
│  │ Avg yield (5Y)   0.53%  ││  ← fiveYearAvgDividendYield
│  │ Est. annual inc $ 9.47  ││  ← shares × price × 5Y yield / 100; shown when shares > 0
│  └─────────────────────────┘│
│                             │
│  Transactions       [+ Add] │
│  BUY  01 Jan 2024           │
│  5 shares @ $ 142.00        │
│                             │
│  Dividends    [⟳] [+ Add]  │
│  PAID  15 Feb 2024          │
│  $ 0.24/share · Total $2.40 │
│  EXPECTED  15 May 2026      │
│  $ 0.25/share · Est. $2.30  │
│                             │
│  Stock Splits       [+ Add] │
│  4:1  10 Jun 2024           │  ← forward split · delete button
│       forward split     [🗑] │
└─────────────────────────────┘
```

**Price display:** When the screen opens, `_fetchPrice()` checks the in-memory cache. If no quote exists or the cached quote is stale, a fresh quote is fetched from Yahoo Finance / Stooq and written to both the DB cache and `priceQuotesProvider`. This ensures the price shows correctly when navigating directly from the stock list without visiting the Dashboard first. Pull-to-refresh (dragging down on the scrollable body) calls `_fetchPrice(forceRefresh: true)`, which always fetches a new quote regardless of staleness and shows a `SnackBar` with "Could not refresh price" if the fetch fails.

**Manual price override:** When no market price is available (e.g. OTC or unlisted securities), a **Set price** link replaces the missing price row. Once set, a **(manual)** tag is appended to the price and a **Clear manual price** button appears. Manual prices are never marked stale.

**Change badges:** Three coloured percentage pills (1D / 1W / 1Y) at the bottom of the info card. 1D comes from `PriceQuote.dayChangePct` (Yahoo `regularMarketChangePercent`) with a fallback to first→last of the intraday 1D history when the quote was fetched via Stooq or set manually. 1W is computed from the 1W price history. 1Y comes from `AnalystData.yearChangePct` (Yahoo `52WeekChange`, a fraction stored and converted to % for display). Badges appear only when data is available; all three can be absent simultaneously.

**Price history chart:** A `StockPriceChart` widget between the info card and analysis card. Shows closing prices for the selected range. The Y-axis displays compact price labels in the active currency. A currency toggle (native code · preferred code) appears when a conversion rate is available and switches all chart prices, Y-axis labels, and tooltip between the stock's trading currency and the user's preferred currency. Chart data is cached for 5 minutes per (stockId, range) key.

**Analysis card:** Shows analyst consensus data fetched from Yahoo Finance. A refresh button (↺) in the card header increments `analystRefreshProvider`, which triggers `analystDataProvider` to re-fetch. The card shows "No data available" (with the same refresh button) when the symbol is not covered or the fetch fails. At the bottom of the card a **Dividends subsection** shows: `trailingAnnualDividendRate` (hidden when zero or null), `fiveYearAvgDividendYield` (already a percentage from Yahoo), and an estimated annual income computed as `sharesHeld × currentPrice × fiveYearAvgDividendYield / 100` in the stock's currency (shown only when shares held > 0).

**Splits section:** Below dividends, lists all recorded stock splits (ratio + date + forward/reverse label) with a per-row delete button that shows a confirmation dialog. The "Add" button opens `AddSplitDialog` — a date picker and two integer fields (From / To) with a live description line (e.g. "4:1 forward split — each share becomes 4"). The list is driven by `splitsByStockProvider` (a `StreamProvider`), so it reflects add/delete operations immediately without any manual refresh.

### Desktop
All sections (stock info, analysis, transactions, dividends, splits) displayed in a single scrollable column; no tabs.

---

## 4. Add / Edit Stock

**Purpose:** Create a new stock or edit an existing one.

### Add Stock
ISIN lookup auto-fills symbol, name, exchange, and currency. If multiple listings are found a bottom-sheet picker shows all options with live prices.

```
┌─────────────────────────────┐
│  ← Add Stock                │
│                             │
│  ISIN          [ Lookup ]   │
│  [ US0378331005           ] │
│                             │
│  Ticker symbol              │
│  [ AAPL                   ] │
│                             │
│  Company name               │
│  [ Apple Inc.             ] │
│                             │
│  Exchange                   │
│  [ NASDAQ                 ] │
│                             │
│  Currency                   │
│  [ USD ▾                  ] │  ← auto-filled from ISIN lookup
│                             │
│  Broker                     │
│  [ Scalable Capital ▾     ] │  ← pre-selected (last used)
│                             │
│  Dividend Reinvestment (DRIP)│
│  [ OFF                  ○ ] │
│                             │
│        [ Save ]             │
└─────────────────────────────┘
```

### Edit Stock
Same fields as Add, but ISIN is read-only. A **Research** button next to the ISIN field re-runs the OpenFIGI lookup and shows the same listing picker as Add Stock, letting the user update symbol, name, exchange, and currency in one step. Currency can also be corrected directly in the dropdown.

```
┌─────────────────────────────┐
│  ← Edit AAPL                │
│                             │
│  ISIN                       │
│  US0378331005 [Research]    │
│                             │
│  Ticker symbol              │
│  [ AAPL                   ] │
│                             │
│  … (same fields as Add) …   │
│                             │
│  [ Save ]  [ Delete stock ] │
└─────────────────────────────┘
```

When symbol or currency changes on save, the cached price is cleared and re-fetched immediately (before navigating back), and the analyst data refresh counter is incremented so stale analyst targets are not shown.

---

## 5. Add / Edit Transaction

```
┌─────────────────────────────┐
│  ← Add Transaction          │
│  AAPL — Apple Inc.          │
│                             │
│  Type                       │
│  ( ● ) Buy    (   ) Sell    │
│                             │
│  Date & Time                │
│  [ 12 May 2026  14:30     ] │
│                             │
│  Number of shares           │
│  [ 10                     ] │
│                             │
│  Price per share            │
│  [ 189.40           USD   ] │
│                             │
│  Fees / Commission          │
│  [ 3.99             USD   ] │
│                             │
│  Notes (optional)           │
│  [                        ] │
│                             │
│        [ Save ]             │
└─────────────────────────────┘
```

---

## 6. Add / Edit Stock Split

```
┌─────────────────────────────┐
│  ← Record Stock Split       │
│  NVDA — NVIDIA Corp.        │
│                             │
│  Date                       │
│  [ 10 Jun 2024            ] │
│                             │
│  Split ratio                │
│  [ 10  ] for [ 1  ]         │
│  (e.g. 10-for-1 means       │
│   1 old share → 10 new)     │
│                             │
│  Preview                    │
│  Before: 5 shares @ $900    │
│  After:  50 shares @ $90    │
│                             │
│        [ Save ]             │
└─────────────────────────────┘
```

---

## 7. Add / Edit Dividend

```
┌─────────────────────────────┐
│  ← Add Dividend             │
│  ALV — Allianz SE           │
│                             │
│  Type                       │
│  ( ● ) Paid  (   ) Expected │
│                             │
│  Payment Date               │
│  [ 02 Jun 2026            ] │
│                             │
│  Amount per share           │
│  [ 4.80             EUR   ] │
│                             │
│  Total received             │
│  [ 96.00            EUR   ] │
│  (auto-filled: 20 × € 4.80) │
│                             │
│  Withholding Tax (optional) │
│  [ 25.60            EUR   ] │
│                             │
│  Notes (optional)           │
│  [                        ] │
│                             │
│        [ Save ]             │
└─────────────────────────────┘
```

---

## 8. Dividend Overview

**Purpose:** All dividends across the portfolio — paid history and upcoming calendar.

### Mobile (tabbed: Received | Upcoming)
```
┌─────────────────────────────┐
│  Dividends                  │
│  ┌──────────┬──────────────┐ │
│  │ Received │   Upcoming   │ │
│  └──────────┴──────────────┘ │
│                             │
│  ── Received tab ──         │
│  Dividend Income      M | Y │  ← DividendIncomeChart card
│  ┌─────────────────────────┐│
│  │ 200┤         ██         ││
│  │ 100┤  ██  ██ ██ ██      ││
│  │    └────────────────────││
│  │   Jan Feb Mar Apr May   ││
│  └─────────────────────────┘│
│                             │
│  Total all-time   € 842.40  │  ← totals summary card
│  ─────────────────────────  │
│  Total 2026       € 186.00  │
│  Total 2025       € 430.00  │
│                             │
│  2026              € 186.00 │  ← year section header
│  ┌─────────────────────────┐│
│  │ ALV  02 Jun  € 96.00    ││
│  │ AAPL 15 May  € 12.40    ││
│  │ ALV  04 Jan  € 77.60    ││
│  └─────────────────────────┘│
│                             │
│  Est. annual income ~€ 42.00│  ← estimatedAnnualDividendProvider card
│  (based on 3 of 4 stocks)   │  ← coverage note
│                             │
│  ── Upcoming tab ──         │
│  Total expected ~€ 108.00   │  ← grand total card
│                             │
│  August 2026      ~€ 12.40  │  ← month section header
│  ┌─────────────────────────┐│
│  │ AAPL  15 Aug  ~€ 12.40  ││
│  └─────────────────────────┘│
│                             │
│  December 2026    ~€ 96.00  │
│  ┌─────────────────────────┐│
│  │ ALV   03 Dec  ~€ 96.00  ││
│  └─────────────────────────┘│
└─────────────────────────────┘
```

**Received tab:** The `DividendIncomeChart` card appears at the top (only paid + confirmed dividends). Below it, a totals summary card shows all-time and per-year totals in the preferred currency, followed by paid dividends grouped under year headers. Pending-confirmation dividends (auto-fetched, unreviewed) appear in a separate section above the totals with a "Review" action. At the bottom of the tab an **estimated annual income card** shows the portfolio-wide dividend income estimate (from `estimatedAnnualDividendProvider`) as "Est. annual income ~€X" with a coverage note indicating how many stocks have cached analyst data contributing to the estimate.

**Upcoming tab:** Expected dividends with `date ≥ today` sorted chronologically and grouped by month. A grand total card shows the sum of all `totalAmount` values that can be converted to the preferred currency (prefixed with `~`). Month headers show the per-month estimated total. Months and the grand total are omitted when no `totalAmount` is set (e.g. for expected dividends recorded without a share count). Tapping any tile opens the edit screen.

### Desktop
Received history and upcoming calendar shown side by side. Upcoming panel includes a simple month-by-month timeline view.

---

## 9. Portfolio Analysis

**Purpose:** Overview of portfolio performance over time and analyst buy recommendations for current holdings. Accessible from the **Analysis** tab in the main navigation.

### Mobile (scrollable)
```
┌─────────────────────────────┐
│  Analysis                   │
│                             │
│  Portfolio History          │  ← PortfolioHistoryChart (stacked area)
│  ┌─────────────────────────┐│
│  │   ████████████████░░░░  ││  ← invested (blue) + unrealised (teal)
│  │   ░░░░░░░░░░░░░░░░░░░░  ││    + realised (dark green)
│  │  2022  2023  2024  2025 ││
│  │  Dividends sub-chart    ││  ← amber bar chart below main chart
│  └─────────────────────────┘│
│                             │
│  Buy recommendations        │  ← shown when analyst data is cached
│  ┌─────────────────────────┐│
│  │ Based on analyst        ││
│  │ consensus for your      ││
│  │ current holdings.       ││
│  ├─────────────────────────┤│
│  │ #1 Apple Inc.           ││
│  │    [Strong Buy] ·14 an. ││
│  │    +21.3% to target     ││
│  │    $ 189.40 → $ 230.00  ││  ← current price & target (quoteCurrency)
│  ├─────────────────────────┤│
│  │ #2 Volkswagen VZ        ││
│  │    [Buy] · 8 analysts   ││
│  │    +12.0% to target     ││
│  └─────────────────────────┘│
└─────────────────────────────┘
```

**Empty state:** When no transactions exist yet, "No data yet. Add transactions to see your portfolio history." replaces the chart. The buy recommendations card is hidden when no analyst data is cached (`buy` or `strong_buy` ratings not yet loaded).

**Data sources:**
- Chart: `portfolioHistoryProvider` (fetches `ChartRange.max` price history for all stocks)
- Recommendations: `topBuysProvider` (reads `analystDataProvider` keepAlive cache — no extra HTTP calls)

### Desktop
Same content, wider layout; chart occupies the full width.

---

## 10. Broker List

```
┌─────────────────────────────┐
│  Brokers            [+ Add] │
│                             │
│  ┌─────────────────────────┐│
│  │ Scalable Capital        ││
│  │ 3 stocks                ││
│  │                   [✏] [🗑]││
│  ├─────────────────────────┤│
│  │ Trade Republic          ││
│  │ 4 stocks                ││
│  │                   [✏] [🗑]││
│  └─────────────────────────┘│
└─────────────────────────────┘
```

---

## 11. Add / Edit Broker

```
┌─────────────────────────────┐
│  ← Add Broker               │
│                             │
│  Name                       │
│  [ Scalable Capital       ] │
│                             │
│  Notes (optional)           │
│  [                        ] │
│                             │
│        [ Save ]             │
└─────────────────────────────┘
```

---

## 12. Settings

```
┌─────────────────────────────┐
│  Settings                   │
│                             │
│  Display                    │
│  Preferred currency  EUR ▾  │
│  Theme          System ▾    │
│  Sparkline period     1M ▾  │  ← SimpleDialog with all 7 ranges
│                             │
│  Portfolio                  │
│  Brokers                [▶] │  ← /settings/brokers
│  Manage your broker accounts│
│                             │
│  Market Data                │
│  Data Provider      Yahoo ▶ │  ← /settings/market-data
│                             │
│  AI                         │
│  AI Portfolio Analysis  [▶] │  ← /settings/ai-analysis
│  Claude-powered insights    │
│                             │
│  Synchronisation            │
│  Import from Broker     [▶] │  ← /settings/broker-import
│  Local Backup           [▶] │  ← /settings/backup
│  Nextcloud Sync         [▶] │  ← /settings/nextcloud
│                             │
│  Notifications              │
│  Enable notifications   [ ] │  ← inline toggle
│  Notification preferences[▶]│  ← /settings/notifications
│                             │
│  About                      │
│  StockManager       v1.0 [▶]│  ← /settings/about
└─────────────────────────────┘
```

**Currency overrides** are accessible from the Preferred currency tile (a chevron leads to `/settings/currency`).

---

## 13. Nextcloud Configuration

```
┌─────────────────────────────┐
│  ← Nextcloud Sync           │
│                             │
│  ╔═════════════════════════╗ │  ← shown only when remote is newer
│  ║ Newer backup on server  ║ │
│  ║ Backup date: 2026-05-12 ║ │
│  ║ [Restore from server]   ║ │
│  ║ [Dismiss]               ║ │
│  ╚═════════════════════════╝ │
│                             │
│  Server URL                 │
│  [ https://cloud.example.com]│
│                             │
│  Username                   │
│  [ myuser                 ] │
│                             │
│  Password / App Token       │
│  [ ••••••••            👁 ] │
│                             │
│  Upload path                │
│  [ /StockManager/         ] │
│                             │
│  Connection successful …    │  ← status after Test Connection
│  Last auto-sync: 2026-05-12 │  ← shown after a sync
│                             │
│  [ Test Connection          ]│
│  [ Backup to Nextcloud now  ]│
│  [ Save                     ]│
└─────────────────────────────┘
```

**Restore flow:** Saving credentials triggers a remote check. If the server has a newer backup, a dialog asks "Restore from server?" before the screen closes. Auto-upload is suppressed while a restore is pending.

---

## 14. Notification Preferences

```
┌─────────────────────────────┐
│  ← Notifications            │
│                             │
│  Enable notifications       │
│  [ ON                   ● ] │
│                             │
│  Price Alerts               │
│  Alert when price moves by  │
│  [ 5 ] %                    │
│                             │
│  Dividend Alerts            │
│  Alert [ 3 ] days before    │
│  expected payment date      │
│                             │
│  Push notifications         │  ← Android only (hidden on desktop)
│  [ ON                   ● ] │
│  (requires Internet)        │
└─────────────────────────────┘
```

---

## 15. Currency Overrides

```
┌─────────────────────────────┐
│  ← Currency Overrides [+ Add]│
│                             │
│  ┌─────────────────────────┐│
│  │ USD → EUR               ││
│  │ Rate: 0.9210  [manual]  ││
│  │ Set: 10 May 2026  [✏][🗑]││
│  ├─────────────────────────┤│
│  │ GBP → EUR               ││
│  │ Rate: 1.1840  [live]    ││
│  │ Updated: 12 May 14:29   ││
│  └─────────────────────────┘│
└─────────────────────────────┘
```

---

## 16. Market Data Settings

**Purpose:** Select the market data provider for analyst consensus data and configure the Finnhub API key.

```
┌─────────────────────────────┐
│  ← Market Data              │
│                             │
│  Data Provider              │
│  ┌─────────────────────────┐│
│  │ (●) Yahoo Finance       ││  ← default, no setup required
│  │     Default, no setup   ││
│  ├─────────────────────────┤│
│  │ ( ) Finnhub             ││  ← requires free account
│  │     Free account reqd.  ││
│  └─────────────────────────┘│
│                             │
│  ── shown when Finnhub ──   │
│  Finnhub API Key            │
│  [ ••••••••••••        👁 ] │  ← obscured, show/hide toggle
│                             │
│  [Get free API key at       │
│   finnhub.io]               │  ← TextButton, shows snackbar with URL
│                             │
│  [ Save API key             ]│
│                             │
│  Note: Finnhub works best   │
│  for US-listed stocks.      │
│  International: use         │
│  EXCHANGE:SYMBOL format     │
│  (e.g. XETRA:ALV).         │
└─────────────────────────────┘
```

**Behaviour:**
- Selecting a provider saves immediately (no Save button needed for the radio selection).
- The API key section is shown only when Finnhub is selected.
- The API key is stored in `flutter_secure_storage`; it is never written to the SQLite database.
- Switching providers or saving a new API key invalidates all cached analyst data so the next Analysis tab open re-fetches from the new source.
- The "API key required" prompt in the Analysis card (when key is not set) deep-links directly to this screen.

---

## 17. AI Portfolio Analysis

**Purpose:** Conversational analysis of the user's portfolio via a user-supplied LLM API key.

### Mobile (idle state)
```
┌─────────────────────────────┐
│  AI Portfolio Analysis  [🔑]│
│                             │
│  ╔═════════════════════════╗ │  ← Privacy notice (always shown)
│  ║ ⓘ Your portfolio data  ║ │
│  ║ is sent to the AI      ║ │
│  ║ provider. See Privacy  ║ │
│  ║ Policy for details.    ║ │
│  ╚═════════════════════════╝ │
│                             │
│  Buy recommendations in your│  ← _TopBuysSection (buy/strong_buy only)
│  portfolio                  │
│  ┌─────────────────────────┐│
│  │ AAPL     [Strong Buy]   ││  ← name + coloured badge
│  │ AAPL · 14 analysts ·   ││
│  │ +21.3% to target        ││
│  ├─────────────────────────┤│
│  │ VOW3     [Buy]          ││
│  │ VOW3 · 8 analysts ·    ││
│  │ +12.0% to target        ││
│  └─────────────────────────┘│
│                             │
│  Quick analysis             │
│  ┌──────────────────────────┐│  ← ActionChip prompts
│  │ Summarise my portfolio…  ││
│  │ Identify concentration…  ││
│  │ Which positions have…    ││
│  └──────────────────────────┘│
│  Or type a custom question  │
│                             │
│  ─────────────────────────── │
│  [ Ask about your portfolio…]│  ← input bar
│                         [→] │
└─────────────────────────────┘
```

### Mobile (done state)
```
┌─────────────────────────────┐
│  AI Portfolio Analysis [↺][🔑]│  ← reset button appears
│                             │
│  ╔═════════════════════════╗ │
│  ║ ✨ AI Analysis          ║ │
│  ║ Your portfolio shows …  ║ │
│  ║ (Markdown rendered)     ║ │
│  ╚═════════════════════════╝ │
│                             │
│  ┌─────────────────────────┐│  ← Suggested stocks to add
│  │ + Suggested stocks      ││
│  │ NOVO-B · Novo Nordisk   ││
│  │ Strong healthcare…      ││
│  │                  [Add]  ││
│  └─────────────────────────┘│
│                             │
│  ─────────────────────────── │
│  [ Ask a follow-up…        ]│
│                         [→] │
└─────────────────────────────┘
```

**Buy recommendations panel** — visible only in the idle state before a query is submitted. Shows currently-held positions where the analyst consensus (from the `analystDataProvider` keepAlive cache) is `buy` or `strong_buy`, sorted strong_buy first then by highest upside-to-analyst-target. Tapping a tile navigates to the stock detail screen. Hidden if no analyst data is loaded yet or no buy ratings exist in the portfolio.

**Suggested stocks** — if the LLM response contains a `---STOCK_SUGGESTIONS---` block, the parsed `{isin, name, reason}` objects are shown as tiles below the response. Tapping "Add" opens the Add Stock screen pre-filled with the ISIN.

---

## 18. AI Analysis Settings

```
┌─────────────────────────────┐
│  ← API Key & Model          │
│                             │
│  Provider                   │
│  ( ● ) Claude (Anthropic)   │
│  (   ) Groq (free)          │
│  (   ) Gemini (free)        │
│                             │
│  API Key                    │
│  [ ••••••••••••••      👁 ] │
│                             │
│  Model                      │
│  ( ● ) claude-opus-4-7      │
│  (   ) claude-sonnet-4-6    │
│                             │
│  [ Save                    ]│
└─────────────────────────────┘
```

---

## Screen Flow Summary

```
Dashboard                          (/  — tab 1)
  └─→ Stock detail (tap a tile)
        └─→ Add / edit transaction
        └─→ Add / edit dividend
        └─→ Record split
        └─→ Edit stock

Stocks                             (/stocks  — tab 2)
  ├─→ Add stock
  └─→ Stock detail
        └─→ (same as Dashboard → Stock detail)

Dividends                          (/dividends  — tab 3)
  └─→ Stock detail (tap a dividend row)

Analysis                           (/analysis  — tab 4)
  (portfolio history chart + buy recommendations — no sub-routes)

Settings                           (/settings  — tab 5)
  ├─→ Portfolio
  │     └─→ Brokers (/settings/brokers)
  │           ├─→ Add broker
  │           └─→ Edit broker
  ├─→ Market Data  (/settings/market-data)
  ├─→ AI Portfolio Analysis (/settings/ai-analysis)
  │     └─→ Provider / key / model (/settings/ai-analysis/key)
  ├─→ Import from Broker (/settings/broker-import)
  │     └─→ Flatex import (/settings/broker-import/flatex)
  ├─→ Local Backup (/settings/backup)
  ├─→ Nextcloud Sync (/settings/nextcloud)
  ├─→ Notification preferences (/settings/notifications)
  ├─→ Currency overrides (/settings/currency)
  └─→ About (/settings/about)
        ├─→ Privacy policy (/settings/about/privacy-policy)
        └─→ App logs (/settings/about/logs)
```
