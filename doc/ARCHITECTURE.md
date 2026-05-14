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

Rate lookup uses the **price currency reported by Yahoo Finance** (`PriceQuote.currency`) rather than the stored `stock.currency`. This ensures correct conversion even when the stored currency was recorded incorrectly at creation time. If no exchange rate is available for the price currency, a missing-rate badge is displayed on the dashboard tile and no conversion is applied.

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

### 5.8 Nextcloud Sync Strategy

#### Backup format
Sync uses a **ZIP archive** containing JSON files (`brokers.json`, `stocks.json`, `transactions.json`, `dividends.json`, `stock_splits.json`, `meta.json`). This is handled by `BackupService.exportToZip()` / `importFromBytes()`. A separate `BackupService.exportToOds()` produces a human-readable ODS spreadsheet for the manual export/share feature. The ZIP backup filename pattern is `stockmanager_backup_YYYY-MM-DD.zip`.

#### Sync triggers
`NextcloudSyncNotifier` (a Riverpod `NotifierProvider`) manages sync state and triggers:

| Trigger | Behaviour |
|---|---|
| App startup (4 s delay) | Check remote for newer backup; if found set `pendingRestore`; otherwise upload |
| After saving credentials | Immediately check remote via `checkForRemoteBackup()` |
| Data mutation | `dataVersionProvider` increments; sync debounced by 5 s |
| Manual "Backup now" tap | `syncNow()` called directly |

#### Bidirectional conflict resolution
On startup and after a credential save the app calls `findLatestBackup()` (WebDAV PROPFIND) and compares `backupDate` with `settings.lastSyncAt`. If the remote backup is newer, `pendingRestore` is set in `NextcloudSyncState` and:
- A card is shown on the Nextcloud settings screen with "Restore from server" / "Dismiss".
- On first launch a dialog is shown immediately after credential save.
Auto-upload is **suppressed** while a restore is pending user decision.

On "Restore": `downloadFile()` fetches the ZIP bytes and `importFromBytes()` replaces all local data atomically inside a Drift transaction. `lastSyncAt` is updated in settings.

#### Secure storage keys
| Key | Value |
|---|---|
| `nextcloud_password` | Nextcloud password / app token |
| `nextcloud_cert_fingerprint` | Pinned SHA-256 fingerprint for self-signed certs |
| `last_used_broker_id` | Pre-selects broker on the Add Stock screen |

### 5.9 Self-Signed Certificate Support
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
