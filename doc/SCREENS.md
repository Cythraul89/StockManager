# StockManager — Screen Designs

All screens exist in two layout variants selected automatically by the adaptive shell:
- **Mobile** (< 600 dp): single column, bottom navigation bar with 5 tabs.
- **Desktop** (≥ 600 dp): persistent left sidebar (240 dp) + content area; master-detail split where noted.

---

## Navigation Structure

**Mobile — bottom bar tabs**
```
[ Dashboard ]  [ Stocks ]  [ Dividends ]  [ Brokers ]  [ Settings ]
```

**Desktop — left sidebar**
```
┌────────────────────┐
│  StockManager      │
│  ───────────────── │
│  Dashboard         │
│  Stocks            │
│  Dividends         │
│  Brokers           │
│  ────────────────── │
│  Settings          │
│  Sync  [●]        │
└────────────────────┘
```
The sync status indicator (●) shows last sync time and triggers a manual sync on tap.

---

## 1. Dashboard

**Purpose:** At-a-glance portfolio health — total value, P&L, upcoming dividends, top movers.

### Mobile
```
┌─────────────────────────────┐
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
│  Holdings                   │
│  ┌─────────────────────────┐│
│  │ AAPL [Buy] ╭╮  +3.2% €189││  ← badge · sparkline · value
│  │ MSFT [Hold]╯╰  -1.1% €412││
│  │ VOW3 [Buy] ╭─  +0.8% € 92││
│  └─────────────────────────┘│
└─────────────────────────────┘
```

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

**Analysis card:** Shows analyst consensus data fetched from Yahoo Finance. A refresh button (↺) in the card header increments `analystRefreshProvider`, which triggers `analystDataProvider` to re-fetch. The card shows "No data available" (with the same refresh button) when the symbol is not covered or the fetch fails.

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
│  Dividend Income      M | Y │  ← DividendIncomeChart card
│  ┌─────────────────────────┐│
│  │ 200┤         ██         ││  ← bar chart, monthly/yearly toggle
│  │ 100┤  ██  ██ ██ ██      ││
│  │    └────────────────────││
│  │   Jan Feb Mar Apr May   ││
│  └─────────────────────────┘│
│                             │
│  ── Received tab ──         │
│  Total all-time   € 842.40  │
│  Total 2026       € 186.00  │
│  Total 2025       € 430.00  │
│                             │
│  ─ 2026 ─                   │
│  ALV  02 Jun  € 96.00       │
│  AAPL 15 May  € 12.40       │
│  ALV  04 Jan  € 77.60       │
│                             │
│  ── Upcoming tab ──         │
│  AAPL  15 Aug 2026 ~€ 12    │
│  ALV   03 Dec 2026 ~€ 96    │
└─────────────────────────────┘
```

**Dividend Income Chart:** A `DividendIncomeChart` card appears above the tab bar whenever at least one paid + confirmed dividend exists. A Monthly / Yearly toggle (top-right of the card) switches the bucket granularity. All amounts are converted to the preferred currency using live exchange rates; dividends whose currency has no available rate are excluded rather than mixed in at the wrong scale. Bar width and X-axis label density adapt to the number of buckets (≤12 / ≤24 / >24). Tapping a bar shows a tooltip with the full period label and the total amount.

### Desktop
Received history and upcoming calendar shown side by side. Upcoming panel includes a simple month-by-month timeline view.

---

## 9. Broker List

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

## 10. Add / Edit Broker

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

## 11. Settings

```
┌─────────────────────────────┐
│  Settings                   │
│                             │
│  Display                    │
│  Preferred currency  EUR ▾  │
│  Theme          System ▾    │
│  Sparkline period     1M ▾  │  ← opens SimpleDialog with all 7 ranges
│                             │
│  Nextcloud Sync         [▶] │
│  Last sync: 12 May 14:30    │
│                             │
│  Notifications          [▶] │
│  Price alerts, dividends    │
│                             │
│  Currency Overrides     [▶] │
│  Manual exchange rates      │
│                             │
│  About                  [▶] │
└─────────────────────────────┘
```

---

## 12. Nextcloud Configuration

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

## 13. Notification Preferences

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

## 14. Currency Overrides

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

## Screen Flow Summary

```
Dashboard
  └─→ Stock detail (tap a top mover)
        └─→ Add transaction
        └─→ Add dividend
        └─→ Record split
        └─→ Edit stock

Stocks
  ├─→ Add stock
  └─→ Stock detail
        └─→ (same as above)

Dividends
  └─→ Stock detail (tap a dividend row)

Brokers
  ├─→ Add broker
  └─→ Edit broker

Settings
  ├─→ Nextcloud configuration
  ├─→ Notification preferences
  └─→ Currency overrides
```
