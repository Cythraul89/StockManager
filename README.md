# StockManager

A cross-platform personal stock portfolio tracker for Android and desktop (macOS, Windows, Ubuntu). All data stays on your own device and your own Nextcloud — no third-party cloud, no subscriptions.

---

## Features

### Portfolio tracking
- **Multi-broker support** — manage stocks across multiple brokers
- **ISIN-based stock lookup** — enter an ISIN and name, ticker, exchange, and currency are resolved automatically via OpenFIGI; re-run lookup at any time from the Edit Stock screen
- **Live market prices** — real-time quotes from Yahoo Finance (+ Stooq fallback); last-known prices shown when offline
- **Manual price override** — set a price manually for securities not covered by any market data source; manual prices never expire and take precedence over live quotes
- **Buy / sell transactions** — full history with fees, optional broker order number, and weighted average price calculated automatically
- **Stock splits** — record splits and reverse splits; historical cost-basis stays accurate
- **Realised & unrealised P&L** — per stock and portfolio total, in the preferred display currency
- **Dividends** — track paid and expected dividends; auto-sync from Yahoo Finance with withholding-tax pre-fill and pending-confirmation flow
- **Annual dividend yield** — computed from last 12 months of paid dividends; for fixed-income assets (bonds, lending funds) a manual **annual interest / yield %** can be entered as an override
- **Dividend reinvestment (DRIP)** — flag a stock as accumulating to skip auto-synced dividend income
- **Preferred display currency** — convert everything to one currency; manual exchange rate overrides supported

### Analysis
- **Portfolio history chart** — stacked area chart of invested capital, unrealised P&L, realised P&L, and dividends across calendar years, with a linear two-year forecast
- **Analyst consensus** — target price (mean / low / high range bar), recommendation rating (Strong Buy → Sell), consensus breakdown, 52-week range, and valuation metrics (P/E, EPS, EV/EBITDA, P/B, PEG, FCF yield) from Yahoo Finance or Finnhub
- **Top buy recommendations** — dashboard panel and dedicated Analysis screen list your current holdings with `buy` or `strong_buy` ratings, ranked by strong-buy first then upside to analyst mean target
- **AI portfolio analysis** — send your portfolio to Claude (Anthropic), Groq, or Gemini for a streamed Markdown analysis; predefined prompt chips cover concentration, sector exposure, P&L trends, and dividend income; LLM can suggest new stocks to add with one-tap ISIN pre-fill
- **Price history chart** — per-stock chart with 1D / 1W / 1M / 6M / 1Y / 5Y / MAX ranges, buy/sell overlays, currency toggle, and mini sparklines on the dashboard

### Alerts & background checks (Android)
- **Price alerts** — notify when a stock moves by a configurable % threshold
- **Trailing stop-loss** — per-stock drop-from-peak threshold; high-water mark tracked automatically
- **Analyst rating change** — notify when the consensus rating changes for a held stock
- **Dividend reminders** — notify N days before an expected payment
- Background checks run via **WorkManager** (~15 min interval, network required); no Firebase / FCM dependency

### Data & sync
- **Nextcloud sync** — ZIP backup (JSON) and human-readable ODS export to your own Nextcloud via WebDAV; self-signed certificates supported via SHA-256 fingerprint pinning
- **Broker CSV import** — import transaction history from Flatex "Orders" CSV; unpriced rows estimated from historic closing prices via Yahoo Finance
- **Offline-first** — fully functional without internet (except live prices and sync)
- **Adaptive UI** — sidebar + master-detail on desktop, bottom-nav single-column on mobile; dark mode follows system preference
- **Crash diagnostics** — startup crash log survives a hard process kill; shown on next launch before the main app starts

---

## Platforms

| Platform | Minimum version |
|---|---|
| Android | Android 13 |
| macOS | macOS 15 |
| Ubuntu | Ubuntu 24.04 |
| Windows | Windows 11 |

---

## Tech Stack

| Concern | Choice |
|---|---|
| Framework | Flutter (Dart) |
| State management | Riverpod |
| Local database | Drift (SQLite) |
| Navigation | go_router |
| HTTP client | Dio |
| Live prices | Yahoo Finance (unofficial JSON) + Stooq CSV fallback |
| Analyst data | Yahoo Finance quoteSummary · Finnhub (optional, free API key) |
| Currency rates | Frankfurter (api.frankfurter.app) — ECB data, no key required |
| ISIN lookup | OpenFIGI API |
| Nextcloud sync | WebDAV |
| Backup format | ZIP (JSON) for sync · ODS for human-readable export |
| Background tasks | WorkManager (Android only) |
| Local notifications | flutter_local_notifications (all platforms) |
| Markdown rendering | flutter_markdown |
| AI analysis | Anthropic Claude · Groq · Google Gemini (user-selectable, own key) |

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) — stable channel
- Android: Android SDK + JDK 17
- Linux: `sudo apt-get install clang cmake ninja-build libgtk-3-dev libsecret-1-dev`
- Windows: Visual Studio 2022 with "Desktop development with C++" workload
- macOS: Xcode 15+

### Run locally

```bash
git clone https://github.com/Cythraul89/StockManager.git
cd StockManager/src
flutter pub get
dart run build_runner build   # generate Drift .g.dart files
flutter run                   # connected device / default desktop target
flutter devices               # list available targets
```

### Build

```bash
cd src

# Android
flutter build apk --debug

# Linux
flutter build linux --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release
```

---

## Nextcloud Setup

1. Open **Settings → Nextcloud Sync** in the app
2. Enter your server URL, username, and password / app token
3. If your server uses a self-signed certificate, tap **Test Connection** — the app shows the certificate fingerprint for you to approve and pin
4. Choose the upload path and how many previous backups to keep (default: 5)
5. Tap **Sync Now** or let auto-sync handle it (triggers on every data change, debounced 5 s)

The exported ODS file contains separate sheets for brokers, stocks, transactions, dividends, and a portfolio summary; it can be opened in LibreOffice Calc or OnlyOffice.

---

## AI Analysis Setup

1. Open **Settings → AI Analysis**
2. Select a provider: **Claude** (Anthropic), **Groq** (free tier), or **Gemini** (free tier)
3. Enter your API key for the selected provider
4. Choose a model (defaults: `claude-opus-4-7`, `llama-3.3-70b-versatile`, `gemini-2.0-flash`)
5. Navigate to **Settings → AI Analysis** (main nav) to run a query

Your portfolio data is sent to the selected provider on each request. No data is sent automatically or in the background.

---

## CI / CD

GitHub Actions workflows are in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | Push to `develop` / `main`, PRs to `main` | Analyze (`--fatal-infos`), test, build all four platforms |
| `release.yml` | Push a `v*.*.*` tag | Build, sign, and publish artifacts to a GitHub Release |

### Secrets required for release builds

| Secret | Description |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded Android upload keystore |
| `ANDROID_KEY_ALIAS` | Key alias in the keystore |
| `ANDROID_KEY_PASSWORD` | Key password |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `MACOS_CERTIFICATE` | Base64-encoded Developer ID `.p12` certificate *(optional)* |
| `MACOS_CERTIFICATE_PWD` | Password for the `.p12` *(optional)* |

To create a release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

---

## Project Structure

```
src/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── database/        # Drift tables and DAOs (schema v17)
│   │   ├── services/        # Market data, currency, AI (Claude/Groq/Gemini),
│   │   │                    #   Nextcloud, backup, notifications, log
│   │   ├── models/          # Immutable domain models
│   │   ├── calculators/     # P&L, average price, dividend yield
│   │   └── utils/           # Formatting, decimal math, date helpers
│   ├── features/
│   │   ├── dashboard/       # Portfolio summary, allocation chart, sparklines
│   │   ├── stocks/          # Stock list, detail, edit, price chart, analyst card
│   │   ├── transactions/    # Add / edit transactions
│   │   ├── dividends/       # Dividend overview, add / edit dividends
│   │   ├── portfolio_analysis/  # History chart + top buy recommendations
│   │   ├── analysis/        # AI portfolio analysis (Claude / Groq / Gemini)
│   │   ├── brokers/         # Broker management (moved to Settings)
│   │   └── settings/        # All settings screens + Flatex CSV import
│   └── shell/
│       ├── adaptive_shell.dart   # Switches between mobile and desktop layout
│       ├── mobile_shell.dart     # Bottom navigation bar
│       └── desktop_shell.dart    # Persistent sidebar + content area
├── test/                    # 106 unit tests
doc/
├── REQUIREMENTS.md
├── ARCHITECTURE.md
├── CLASS_DIAGRAM.md
└── SCREENS.md
.github/
└── workflows/
    ├── ci.yml
    └── release.yml
```

---

## Documentation

- [Requirements](doc/REQUIREMENTS.md)
- [Architecture](doc/ARCHITECTURE.md)
- [Class Diagram](doc/CLASS_DIAGRAM.md)

---

## License

[GPL-3.0](LICENSE)
