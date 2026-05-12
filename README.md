# StockManager

A cross-platform personal stock portfolio tracker for Android and desktop (macOS, Windows, Ubuntu). All data stays on your own device and your own Nextcloud — no third-party cloud, no subscriptions.

---

## Features

- **Multi-broker support** — manage up to 10 brokers and 100 stocks across them
- **ISIN-based stock lookup** — enter an ISIN and name, ticker, exchange and currency are resolved automatically
- **Live market prices** — real-time quotes fetched from the internet; last-known prices shown when offline
- **Buy / sell transactions** — full history with fees, weighted average price calculated automatically
- **Stock splits** — record splits and reverse splits; historical cost-basis stays accurate
- **Realised & unrealised P&L** — per stock and portfolio total
- **Dividends** — track paid dividends and upcoming expected payments; annual yield per stock
- **Dividend reinvestment (DRIP)** — optionally auto-create a buy transaction when a dividend is recorded
- **Preferred display currency** — convert everything to one currency on the dashboard; manual exchange rate overrides supported
- **Nextcloud sync** — exports portfolio data as a timestamped ODS spreadsheet to your own Nextcloud via WebDAV; self-signed certificates supported
- **Offline-first** — fully functional without internet (except live prices and sync)
- **Notifications** — price alerts and upcoming dividend reminders; push notifications on Android via FCM
- **Adaptive UI** — sidebar + master-detail layout on desktop, bottom-nav single-column on mobile
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
| Market data | Yahoo Finance (unofficial JSON endpoint) |
| Currency rates | Open Exchange Rates (free tier) |
| Nextcloud sync | WebDAV |
| ODS export | Custom ODS builder |
| Push notifications | Firebase Cloud Messaging (Android only) |
| Background tasks | WorkManager (Android only) |
| Secure storage | flutter_secure_storage |

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) — stable channel
- Android: Android SDK + JDK 17
- Linux: `sudo apt-get install clang cmake ninja-build libgtk-3-dev`
- Windows: Visual Studio 2022 with “Desktop development with C++” workload
- macOS: Xcode 15+

### Run locally

```bash
git clone https://github.com/Cythraul89/StockManager.git
cd StockManager
flutter pub get
flutter run          # runs on the connected device / default desktop target
flutter devices      # list available targets
```

### Build

```bash
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

---

## Nextcloud Setup

1. Open **Settings → Nextcloud Sync** in the app
2. Enter your server URL, username, and password / app token
3. If your server uses a self-signed certificate, tap **Test Connection** — the app will show the certificate fingerprint for you to approve and pin
4. Choose the upload path and how many previous exports to keep
5. Tap **Sync Now** or enable auto-sync

The exported ODS file contains separate sheets for brokers, stocks, transactions, dividends, and a summary, and can be opened in LibreOffice Calc or OnlyOffice.

---

## Android Push Notifications

Push notifications (price alerts and dividend reminders when the app is closed) are delivered via Firebase Cloud Messaging on Android. A Firebase project is required:

1. Create a project at [console.firebase.google.com](https://console.firebase.google.com)
2. Add an Android app with the package name matching `android/app/build.gradle`
3. Download `google-services.json` and place it in `android/app/`
4. Enable notifications in **Settings → Notifications** in the app

Desktop platforms use local notifications only — no Firebase setup needed.

---

## CI / CD

GitHub Actions workflows are included in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | Push to `develop` / `main`, PRs to `main` | Analyze, test, build all four platforms |
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

To create a release: tag a commit and push the tag.

```bash
git tag v1.0.0
git push origin v1.0.0
```

---

## Project Structure

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── database/        # Drift tables and DAOs
│   ├── services/        # Market data, currency, Nextcloud, ODS, notifications
│   ├── models/          # Immutable domain models
│   ├── calculators/     # P&L, average price, dividend yield
│   └── utils/
├── features/
│   ├── dashboard/
│   ├── stocks/
│   ├── transactions/
│   ├── dividends/
│   ├── brokers/
│   └── settings/
└── shell/
    ├── adaptive_shell.dart   # Switches between mobile and desktop layout
    ├── mobile_shell.dart     # Bottom navigation bar
    └── desktop_shell.dart    # Persistent sidebar + content area
doc/
├── REQUIREMENTS.md
├── ARCHITECTURE.md
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
- [Screen Designs](doc/SCREENS.md)

---

## License

[GPL-3.0](LICENSE)
