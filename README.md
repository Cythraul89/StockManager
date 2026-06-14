# StockManager

A cross-platform personal stock portfolio tracker for Android and desktop (macOS, Windows, Ubuntu). All data stays on your own device and your own Nextcloud — no third-party cloud, no subscriptions.

---

## Features

- **Multi-broker support** — manage up to 10 brokers and 100 stocks across them
- **ISIN-based stock lookup** — enter an ISIN; name, ticker, exchange, and currency are resolved automatically via OpenFIGI
- **Live market prices** — real-time quotes from Yahoo Finance (Stooq fallback); last-known prices shown when offline
- **Manual price override** — set a custom price for unlisted or OTC securities; never expires, takes precedence over live quotes
- **Buy / sell transactions** — full history with fees; weighted average price calculated automatically
- **Stock splits** — record splits and reverse splits; historical cost-basis stays accurate
- **Realised & unrealised P&L** — per stock and portfolio total
- **Dividends** — track paid and upcoming expected dividends; annual yield per stock
- **Dividend reinvestment (DRIP)** — optionally auto-create a buy transaction when a dividend is recorded
- **Auto-fetched dividends** — sync paid history and next expected dividend from Yahoo Finance with one tap
- **Asset types** — stock / ETF / bond / crypto / other; bonds and impact funds support a manual annual yield % override
- **Analyst data** — consensus rating, price target range, 52-week range, valuation metrics (P/E, EPS, EV/EBITDA, P/B, PEG, FCF yield) via Yahoo Finance or Finnhub
- **Buy recommendations** — dashboard panel and Analysis tab highlight held stocks rated Buy/Strong Buy with upside-to-target
- **Portfolio history chart** — stacked area chart of invested capital, unrealised P&L, realised P&L, and dividends across calendar years with a 2-year forecast
- **AI portfolio analysis** — conversational analysis powered by Anthropic Claude, Groq, or Google Gemini (user-supplied API key); streams Markdown responses in real time
- **Broker import** — import transactions from a Flatex CSV export (Ausführungen); more brokers planned
- **Trailing stop-loss alerts** — per-stock drop-from-peak threshold; high-water mark tracked automatically
- **Preferred display currency** — convert everything to one currency; manual exchange rate overrides supported
- **Nextcloud sync** — automatic ZIP backup to your own Nextcloud via WebDAV; self-signed certificates supported
- **Local backup** — export / import a ZIP backup or an ODS spreadsheet (LibreOffice / OnlyOffice compatible)
- **Offline-first** — fully functional without internet (except live prices and sync)
- **Notifications** — price alerts, trailing stop-loss, analyst rating changes, and upcoming dividend reminders; delivered via WorkManager on Android (no server needed)
- **Adaptive UI** — persistent sidebar on desktop, bottom-nav on mobile; master-detail on tablets
- **Dark mode** — follows system preference

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
| Market data | Yahoo Finance (unofficial JSON) + Stooq CSV fallback; Finnhub optional (free API key) |
| Currency rates | Frankfurter (api.frankfurter.app) — free, no key, ECB data |
| ISIN lookup | OpenFIGI (api.openfigi.com) |
| AI analysis | Anthropic Claude / Groq / Gemini — user-selectable, SSE streaming |
| Nextcloud sync | WebDAV |
| Backup format | ZIP (JSON) for sync; ODS for human-readable export |
| Background tasks | WorkManager (Android only) — price, rating, dividend, trailing stop-loss checks |
| Local notifications | flutter_local_notifications |
| Markdown rendering | flutter_markdown |
| Secure storage | flutter_secure_storage (`last_used_broker_id` only) |

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
flutter run                   # connected device or default desktop target
flutter devices               # list available targets
```

### Build

```bash
cd src

# Android
flutter build apk --release          # APK
flutter build appbundle --release    # AAB (Play Store)

# Linux
flutter build linux --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release
```

> **Note:** Platform directories (`android/`, `linux/`, `windows/`, `macos/`) are not committed. Run `flutter create --platforms=<platform> .` inside `src/` to scaffold them before building.

---

## Nextcloud Setup

1. Open **Settings → Nextcloud Sync** in the app
2. Enter your server URL, username, and password / app token
3. If your server uses a self-signed certificate, tap **Test Connection** — the app shows the SHA-256 fingerprint for you to approve and pin
4. Choose the upload path and how many previous backups to keep (default: 5)
5. Tap **Backup now** or let auto-sync handle it (triggers on startup and after data changes)

The sync format is a timestamped ZIP archive (`stockmanager_backup_YYYY-MM-DDTHH-MM-SSZ.zip`) containing JSON files for all data. A separate **ODS spreadsheet** (7 sheets: summary, brokers, stocks, transactions, paid dividends, expected dividends, exchange rates) can be exported from **Settings → Local Backup** and opened in LibreOffice Calc or OnlyOffice.

---

## AI Analysis Setup

1. Open **Settings → AI Portfolio Analysis** and tap the key icon
2. Select a provider: **Claude** (Anthropic), **Groq** (free tier), or **Gemini** (free tier, 1M tokens/day)
3. Paste your API key and select a model
4. Return to the Analysis screen and tap a prompt chip or type a question

Portfolio data is serialised to JSON and sent to the provider on each request. No data is sent automatically — all calls are user-triggered.

---

## Android Background Notifications

Background notifications (price alerts, trailing stop-loss, rating changes, dividend reminders) are delivered via **WorkManager** periodic background tasks — no Firebase / FCM setup required. WorkManager runs checks approximately every 15 minutes when a network connection is available.

To enable: open **Settings → Notifications** and toggle on.

---

## CI / CD

GitHub Actions workflows in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | Push to `develop` / `main`, PRs to `main` | Analyze, test, build all four platforms |
| `release.yml` | Push a `v*.*.*` tag | Build, sign, and publish artifacts to a GitHub Release |
| `sbom.yml` | Push / PR | Generate CycloneDX SBOM via Syft |

### Secrets required for release builds

| Secret | Description |
|---|---|
| `ANDROID_RELEASE_KEYSTORE_B64` | Base64-encoded Android upload keystore |
| `ANDROID_KEY_ALIAS` | Key alias in the keystore |
| `ANDROID_KEY_PASSWORD` | Key password |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `MACOS_CERTIFICATE` | Base64-encoded Developer ID `.p12` certificate *(optional)* |
| `MACOS_CERTIFICATE_PWD` | Password for the `.p12` *(optional)* |

```bash
git tag v1.0.0
git push origin v1.0.0
```

---

## Project Structure

```
src/lib/
├── main.dart                        # Entry point, ProviderScope, crash diagnostics
├── app.dart                         # MaterialApp, go_router, theme
├── core/
│   ├── database/                    # Drift tables (schema v17) and DAOs
│   ├── services/                    # HTTP APIs, backup, notifications, WebDAV, LLM
│   ├── models/                      # Immutable domain models (pure Dart)
│   ├── calculators/                 # P&L, average price, dividend yield
│   └── utils/                       # Formatting, date helpers, decimal math
├── features/
│   ├── dashboard/                   # Portfolio summary, history chart, allocation chart
│   ├── stocks/                      # Stock list, detail, price chart
│   ├── transactions/
│   ├── dividends/
│   ├── analysis/                    # AI portfolio analysis (Claude / Groq / Gemini)
│   ├── portfolio_analysis/          # Portfolio Analysis tab (history chart + buy recommendations)
│   └── settings/                    # All settings screens + Flatex import
└── shell/
    ├── adaptive_shell.dart          # Switches between mobile and desktop layout
    ├── mobile_shell.dart            # Bottom navigation bar (5 tabs)
    └── desktop_shell.dart           # Persistent sidebar + content area
doc/
├── REQUIREMENTS.md
├── ARCHITECTURE.md
├── CLASS_DIAGRAM.md
└── SCREENS.md
.github/
└── workflows/
    ├── ci.yml
    ├── release.yml
    └── sbom.yml
```

---

## Documentation

- [Requirements](doc/REQUIREMENTS.md)
- [Architecture](doc/ARCHITECTURE.md)
- [Class Diagram](doc/CLASS_DIAGRAM.md)
- [Screen Designs](doc/SCREENS.md)
- [Developer Guide](CLAUDE.md)

---

## License

[GPL-3.0](LICENSE)
