# StockManager — Architecture

## 1. Technology Stack

| Concern | Library / Tool | Rationale |
|---|---|---|
| Framework | Flutter (Dart) | Single codebase for Android + macOS + Windows + Ubuntu |
| State management | Riverpod | Async-first, composable providers, easy to unit-test |
| Local database | Drift (SQLite) | Type-safe, reactive streams, first-class migration support |
| Navigation | go_router | Declarative, shell routes for adaptive layout, deep-link ready |
| HTTP client | Dio | Interceptors, retry logic, timeout handling |
| Market data | Yahoo Finance (unofficial JSON endpoint) | Free, no API key required for basic quotes |
| Currency rates | Open Exchange Rates (free tier) | Simple JSON, cacheable, supports all ISO 4217 pairs |
| Nextcloud sync | WebDAV over HTTP | Nextcloud's native protocol; no extra server needed |
| ODS export | ods_builder (custom) | OpenDocument ZIP format; no dependency on office suite |
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
│   │   ├── notification_service.dart
│   │   └── ods_export_service.dart
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
| symbol | TEXT | e.g. AAPL |
| name | TEXT | e.g. Apple Inc. |
| exchange | TEXT | e.g. NASDAQ |
| currency | TEXT | ISO 4217, e.g. USD |
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
| total_amount | DECIMAL? | null for expected (calculated on read) |
| currency | TEXT | |
| withholding_tax | DECIMAL? | |
| notes | TEXT? | |

**price_cache**
| Column | Type | Notes |
|---|---|---|
| stock_id | UUID (PK, FK stocks) | |
| price | DECIMAL | |
| currency | TEXT | |
| fetched_at | DATETIME | |

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
Raw transaction rows are never modified when a stock split is recorded. The domain calculator applies a cumulative split multiplier when reading historical transactions, keeping raw data immutable and auditable.

### 5.3 Currency Conversion
Exchange rates are fetched on demand and cached with a 1-hour TTL. When offline, the most recent cached rate is used with a staleness indicator shown in the UI. Manual overrides stored in the database bypass the TTL entirely.

### 5.4 Financial Arithmetic
All monetary values are stored and calculated as `Decimal` (via the `decimal` package), never `double`, to avoid floating-point rounding errors.

### 5.5 Background Price Alerts on Android
True FCM push requires a backend server to send messages. To avoid a server dependency, price alerts on Android are implemented using **WorkManager** (periodic background task, ~15 min minimum interval). The task fetches latest prices, checks thresholds, and fires a local notification if triggered. FCM infrastructure is included in the project so a self-hosted backend can be added later without client changes.

### 5.6 Nextcloud Sync Strategy
The local SQLite database is the source of truth. Sync is one-directional: local data → ODS export → uploaded to Nextcloud via WebDAV PUT. The ODS filename includes a timestamp (e.g. `stockmanager_2026-05-12T14-30.ods`). Previous exports are retained on Nextcloud (configurable count).

### 5.7 ODS Structure
The exported ODS file contains the following sheets in order:

| Sheet | Contents |
|---|---|
| Summary | Total portfolio value, P&L, preferred currency, sync timestamp |
| Brokers | All brokers with names and notes |
| Stocks | All stocks with current price, value, avg buy price, P&L |
| Transactions | Full transaction history across all stocks |
| Dividends Paid | All recorded dividend payments |
| Dividends Expected | All upcoming expected dividends |
| Exchange Rates | Rates used at time of export |

---

## 6. Navigation Map

```
/                        → Dashboard
/stocks                  → Stock list
/stocks/:id              → Stock detail
/stocks/:id/edit         → Edit stock
/stocks/add              → Add stock
/stocks/:id/transactions/add   → Add transaction
/stocks/:id/dividends/add      → Add dividend (paid or expected)
/dividends               → Dividend overview
/brokers                 → Broker list
/brokers/add             → Add broker
/brokers/:id/edit        → Edit broker
/settings                → Settings
/settings/nextcloud      → Nextcloud configuration
/settings/currency       → Currency preferences & overrides
/settings/notifications  → Notification preferences
```

All routes are nested inside the `ShellRoute` so the navigation chrome (sidebar / bottom bar) is always present.
