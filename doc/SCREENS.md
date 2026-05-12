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
│  │+€ 6,430  │ │YTD €Ɔ420 │  │
│  └──────────┘ └──────────┘  │
│                             │
│  Top Movers                 │
│  ┌─────────────────────────┐│
│  │ AAPL  +3.2%    € 189.40 ││
│  │ MSFT  -1.1%    € 412.00 ││
│  │ VOW3  +0.8%    €  92.50 ││
│  └─────────────────────────┘│
│                             │
│  Upcoming Dividends         │
│  ┌─────────────────────────┐│
│  │ AAPL  15 May  € 12.40   ││
│  │ ALV    2 Jun  € 84.00   ││
│  └─────────────────────────┘│
└─────────────────────────────┘
```

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

**Purpose:** Full view of one stock — price, positions, P&L, transactions, dividends.

### Mobile (tabbed)
```
┌─────────────────────────────┐
│  ← AAPL — Apple Inc.   [✏] │
│  NASDAQ · USD · Scalable    │
│                             │
│  $ 189.40  ▲ +3.2% today   │
│  € 174.28 (preferred)       │
│                             │
│  ┌────────┬────────┬───────┐ │
│  │Overview│Transact│Divid. │ │
│  └────────┴────────┴───────┘ │
│                             │
│  ── Overview tab ──         │
│  Shares held      10.00     │
│  Avg buy price  $ 145.20    │
│  Total invested € 1,337     │
│  Current value  € 1,743     │
│  Unrealised P&L  +€ 406 ▲  │
│  Realised P&L    +€  80 ▲  │
│  Dividend yield    0.52%    │
│  DRIP             OFF  [⚙] │
└─────────────────────────────┘
```

**Transactions tab**
```
│  Transactions          [+ Add] │
│  ─────────────────────────     │
│  BUY  01 Jan 2024              │
│  5 shares @ $ 142.00  – $ 4.99 │
│  ─────────────────────────     │
│  BUY  15 Mar 2024              │
│  5 shares @ $ 148.40  – $ 4.99 │
```

**Dividends tab**
```
│  Dividends                [+ Add] │
│  ────────────────────────────────   │
│  PAID  15 Feb 2024                │
│  $ 0.24/share · Total $ 2.40      │
│  ────────────────────────────────   │
│  EXPECTED  15 May 2026            │
│  $ 0.25/share · Est. € 2.30       │
```

### Desktop
All three sections (Overview, Transactions, Dividends) displayed simultaneously in a three-column layout without tabs.

---

## 4. Add / Edit Stock

**Purpose:** Create a new stock or edit an existing one.

```
┌─────────────────────────────┐
│  ← Add Stock                │
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
│  [ USD ▾                  ] │
│                             │
│  Broker                     │
│  [ Scalable Capital ▾     ] │
│                             │
│  Dividend Reinvestment (DRIP)│
│  [ OFF                  ○ ] │
│                             │
│        [ Save ]             │
└─────────────────────────────┘
```

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
│  Server URL                 │
│  [ https://cloud.example.com]│
│                             │
│  Username                   │
│  [ myuser                 ] │
│                             │
│  Password / App Token       │
│  [ ••••••••               ] │
│                             │
│  Upload path                │
│  [ /StockManager/         ] │
│                             │
│  Keep last N exports        │
│  [ 5                      ] │
│                             │
│  Auto-sync on data change   │
│  [ ON                   ● ] │
│                             │
│  [ Test Connection ]        │
│  [ Sync Now        ]        │
└─────────────────────────────┘
```

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
