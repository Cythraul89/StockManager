# StockManager — Developer Guide

> Quick reference for working on this codebase. Full architecture details are in
> [`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md). Class diagram is in
> [`doc/CLASS_DIAGRAM.md`](doc/CLASS_DIAGRAM.md).

> **Branch policy**: Always develop and push on the `develop` branch. Never
> push to any other branch without explicit user instruction.

---

## Flutter / Dart version

```
Flutter stable channel   (CI uses subosito/flutter-action@v2, channel: stable)
Dart SDK >=3.3.0 <4.0.0
Java 17 (Android builds only)
```

---

## Key commands

All commands run from `src/`:

```bash
cd src

# Resolve dependencies
flutter pub get

# Generate Drift .g.dart files (REQUIRED after touching any table or DAO)
dart run build_runner build

# Static analysis (mirrors CI — must be clean with --fatal-infos)
flutter analyze --fatal-infos

# Run tests
flutter test

# Run on connected device / default desktop
flutter run

# Build targets
flutter build apk --debug                  # Android (debug, unsigned)
flutter build linux --release
flutter build windows --release
flutter build macos --release
```

---

## Generated code

Drift uses `build_runner` to generate `*.g.dart` files from table and DAO
annotations. These files are **not committed** — every build step regenerates
them. Any change to a file in `core/database/tables/` or `core/database/daos/`
requires running:

```bash
dart run build_runner build
```

The generated file for the main database is `core/database/app_database.g.dart`.
The `DecimalConverter` class (in `core/database/tables/decimal_converter.dart`)
must be imported in `app_database.dart` so the generated code can see it.

---

## Project layout

```
src/
├── lib/
│   ├── main.dart                       # Entry point, ProviderScope bootstrap
│   ├── app.dart                        # MaterialApp, GoRouter, theme
│   ├── core/
│   │   ├── database/
│   │   │   ├── app_database.dart       # @DriftDatabase root
│   │   │   ├── daos/                   # One DAO per aggregate
│   │   │   └── tables/                 # One table per entity + DecimalConverter
│   │   ├── models/                     # Immutable domain models (pure Dart)
│   │   ├── services/                   # HTTP APIs, notifications, WebDAV
│   │   ├── calculators/                # Pure P&L / dividend / position math
│   │   └── utils/                      # Formatting, date helpers, decimal math
│   │       └── app_version.dart        # appVersion / appBuildNumber constants
│   └── features/
│       ├── dashboard/                  # portfolioSummaryProvider + DashboardScreen
│       ├── stocks/                     # stocksProvider, stockActionsProvider
│       ├── transactions/               # AddTransactionScreen
│       ├── dividends/                  # DividendsScreen, AddDividendScreen
│       ├── brokers/                    # BrokersScreen, CRUD screens
│       ├── analysis/                   # AI portfolio analysis feature
│       │   ├── analysis_screen.dart        # Prompt chips, streaming response, ISIN suggestions
│       │   ├── analysis_provider.dart      # AnalysisNotifier, StockSuggestion, _parseSuggestions
│       │   └── ai_analysis_settings_screen.dart  # Provider/key/model picker
│       └── settings/                   # settingsProvider, settingsActionsProvider
│           ├── about_screen.dart           # Version, GPL-3 notice, privacy policy, app logs
│           ├── broker_import_screen.dart   # Broker import entry-point (picker)
│           ├── flatex_import_screen.dart   # Flatex CSV import (parse → preview → import)
│           ├── privacy_policy_screen.dart  # In-app privacy policy viewer
│           ├── logs_screen.dart            # Log viewer with share/clear app-bar actions
│           └── parsers/
│               └── flatex_order_parser.dart  # Parser, FlatexParsedOrder, FlatexUnpricedOrder
└── test/
    ├── widget_test.dart
    ├── manual_price_dialog_test.dart
    ├── calculators/
    ├── utils/
    ├── models/
    ├── database/
    └── parsers/
        └── flatex_order_parser_test.dart
```

---

## Architecture in brief

```
UI (Flutter widgets, ConsumerWidget)
  │ watches
Riverpod providers (FutureProvider / StreamProvider / StateProvider)
  │ calls
DAOs (Drift, typed queries, reactive streams)
  │ persists
SQLite (via Drift / NativeDatabase)

         ┌───────────────────────────┐
         │  Calculators (pure Dart)  │  ← no I/O; consume models, return results
         │  portfolio, pnl, dividend │
         └───────────────────────────┘

         ┌─────────────────────────────────────────┐
         │  Services (HTTP / platform)             │
         │  MarketData · Currency · ISIN · Nextcloud│
         │  Notifications                           │
         └─────────────────────────────────────────┘
```

Providers that **must be overridden** in `ProviderScope` at startup:

| Provider | Concrete value |
|---|---|
| `databaseProvider` | `AppDatabase()` |
| `notificationServiceProvider` | `NotificationService()` |
| `marketDataServiceProvider` | `MarketDataService(dio)` |
| `currencyServiceProvider` | `CurrencyService(dio)` |
| `isinLookupServiceProvider` | `IsinLookupService(dio)` |

---

## Key conventions

- **Decimal, never double** — all monetary values use `package:decimal`. The
  `DecimalConverter` serialises them to/from SQLite text. The extension
  `DecimalX` (in `core/utils/decimal_math.dart`) adds `isZero`, `isPositive`,
  `percentChangeFrom()`, etc.

- **Immutable domain models** — every model has `copyWith()` and extends
  `Equatable`. Database rows (`StockRow`, etc.) are separate classes auto-
  generated by Drift; DAOs map them to domain models.

- **Stock-split-adjusted calculations** — never mutate historical transaction
  rows when a split is recorded. `PortfolioCalculator.calculate()` applies a
  cumulative split ratio on read.

- **Currency conversion at the provider layer** — `portfolioSummaryProvider`
  converts all per-stock values to `preferredCurrency` using `ExchangeRate`.
  Screens never do currency math. Two-step conversion: quote currency →
  `stock.currency` (so P&L arithmetic is in consistent units) → preferred
  currency (for portfolio aggregation).

- **FutureProvider staleness** — `settingsProvider` (a `FutureProvider`) caches
  its result until invalidated. Code that writes to the DB and then immediately
  reads settings must either go through the DAO directly or call
  `ref.invalidate(settingsProvider)`. Never use `saveSettings(staleSnapshot.copyWith(...))`
  to persist a partial update — use a targeted DAO method instead (e.g.
  `updateLastSyncAt()`).

- **Manual price overrides** — stocks without live market data can have a manual
  price set via the Stock Detail screen. Manual prices (`manualOverride = true`
  in `price_cache`) are never marked stale and take precedence over live quotes
  in `priceQuotesProvider`. Use `stockActionsProvider.setManualPrice()` /
  `clearManualPrice()`.

- **Navigator** — GoRouter with a `ShellRoute`. All feature routes live inside
  the shell. Adaptive layout: `DesktopShell` (NavigationRail) at ≥ 600 dp,
  `MobileShell` (BottomNavigationBar) below.

- **Dialog Navigator pitfall** — `showDialog` defaults to `useRootNavigator: true`,
  so the dialog is placed on the *root* navigator. The `builder` callback receives
  a dialog-scoped `BuildContext ctx`. Always use `Navigator.pop(ctx, value)` (the
  dialog's own context), never `Navigator.pop(outerContext, value)` — the outer
  context belongs to the nested ShellRoute navigator, and popping it removes the
  current screen instead of the dialog.

- **Analyzer strictness** — CI runs `flutter analyze --fatal-infos`. Keep
  analysis clean. Notable lint rules already enforced: `use_build_context_synchronously`,
  `deprecated_member_use`, `prefer_const_constructors`, `prefer_const_declarations`.

- **NativeDatabase on main isolate** — `_openConnection()` uses `NativeDatabase(file)`,
  NOT `NativeDatabase.createInBackground()`. The background variant spawns an isolate
  that doesn't inherit Flutter plugin registrations, so `sqlite3_flutter_libs` can't load
  `libsqlite3.so` there, causing a native crash in release builds.

- **Backup consistency** — `exportToZip()` and `exportToOds()` wrap all five DAO reads
  in a single `_db.transaction()` to guarantee an atomic snapshot. Do not add plain
  `await dao.getAll()` calls outside that transaction block. `importFromBytes()` returns
  an `int` skip count (orphaned rows that couldn't be restored); callers must surface
  this to the user if > 0.

- **IsinLookupService contract** — `lookup()` returns:
  - `null` — connection-layer failure (DNS, timeout, no internet)
  - `[]` — server responded but no listings found for the ISIN, or HTTP 4xx/5xx
  - `List<IsinLookupResult>` — at least one listing found
  
  Always check null and empty separately. Do **not** use `results?.firstOrNull` —
  that collapses both failure modes into a single null, masking network errors.

- **Startup crash diagnostics** — `main.dart` maintains a crash log at
  `<documents>/stockmanager_crash.txt`. All writes are synchronous (`writeAsStringSync`
  with `flush: true`) so entries survive a hard process kill. The log is cleared 15 s
  after the first frame to let async provider/DB work settle. A previous crash log is
  shown to the user before the next startup. Note: crashes before `_initCrashLogPath()`
  completes (very early startup) are logged to logcat only, not to the file.

---

## Testing

The test suite lives in `test/` and has **106 tests** across 9 files:

| File | What it covers |
|---|---|
| `test/widget_test.dart` | App renders dashboard (smoke test) |
| `test/manual_price_dialog_test.dart` | ManualPriceDialog validation and return values |
| `test/calculators/portfolio_calculator_test.dart` | `PortfolioCalculator`: single buy, weighted avg, partial/full sell, 4:1 and 1:2 splits, `splitMultiplierAfter`, `sharesAtDate` |
| `test/calculators/pnl_calculator_test.dart` | `PnlCalculator`: unrealised/realised P&L, fee handling, oversell clamping, `convert` |
| `test/calculators/dividend_calculator_test.dart` | `DividendCalculator`: `estimatedTotal`, allTime/yearTotal, annualYield 12-month window, zero-division guard, `convert`, `Dividend.netAmount`, `manualYieldPct` fallback |
| `test/utils/decimal_math_test.dart` | `DecimalX` predicates, `percentChangeFrom`, `weightedAverage`, `clampMin` |
| `test/models/exchange_rate_test.dart` | `ExchangeRate.find`, `convert`, `isStale`, Equatable equality |
| `test/models/stock_test.dart` | `Stock.copyWith` sentinel pattern (`manualYieldPct`, `trailingStopPct`), Equatable equality |
| `test/database/trailing_stop_test.dart` | `StocksDao.updateTrailingStop` / `updateTrailingStopHighWater` with in-memory Drift DB |
| `test/parsers/flatex_order_parser_test.dart` | `FlatexOrderParser`: all row types, skip counters, date format variants, ISIN/WKN split, real-world export format |

### Widget test setup

Key overrides required for `widget_test.dart`:

```dart
ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(AppDatabase.forTesting(NativeDatabase.memory())),
    notificationServiceProvider.overrideWithValue(NotificationService()),
    marketDataServiceProvider.overrideWith((ref) => throw UnimplementedError()),
    // Prevents Drift StreamQueryStore from creating cleanup timers inside
    // testWidgets' FakeAsync zone (would cause "Timer still pending" failures).
    portfolioSummaryProvider.overrideWith((ref) async => PortfolioSummary(...)),
  ],
  child: const StockManagerApp(),
)
```

Close the in-memory DB via `tester.runAsync(db.close)` to exit the FakeAsync
zone before Drift's internal futures resolve.

### DB unit test setup

Database tests use `AppDatabase.forTesting(NativeDatabase.memory())` with
`setUp`/`tearDown` to give each test a fresh isolated schema. FK constraints
are enforced — insert a broker before inserting a stock.

---

## CI pipeline (`.github/workflows/ci.yml`)

| Job | Runner | Key steps |
|---|---|---|
| Analyze & Test | ubuntu-latest | `pub get` → `build_runner` → `flutter analyze --fatal-infos` → `flutter test` |
| Build Android | ubuntu-latest | pub get → build_runner → `flutter create --platforms=android .` → Python patch: set `compileSdk = 36` in `android/app/build.gradle.kts`, enable core library desugaring, rename `compileSdkVersion N` → `compileSdk N` (AGP 9+ new DSL) and bump to 36 in `file_picker`'s pub-cache `build.gradle` → `flutter build apk --debug` |
| Build Linux | ubuntu-latest | apt-get `clang cmake ninja-build libgtk-3-dev libsecret-1-dev` → pub get → build_runner → `flutter create --platforms=linux .` → `flutter build linux --release` |
| Build Windows | windows-latest | pub get → build_runner → `flutter create --platforms=windows .` → `flutter build windows --release` |
| Build macOS | macos-latest | pub get → build_runner → `flutter create --platforms=macos .` → `flutter build macos --release` → ad-hoc re-sign (no sandbox entitlements) |

All JavaScript actions run on Node.js 24 (`FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` workflow env).

Platform directories (`android/`, `linux/`, `windows/`, `macos/`) are **not
committed**; they are scaffolded on the fly with `flutter create --platforms=<platform> .`.

Build artifacts are uploaded via `actions/upload-artifact@v4` and downloadable
from the Actions run summary for 90 days.

## SBOM (`.github/workflows/sbom.yml`)

Generates a **CycloneDX JSON** Software Bill of Materials on every push/PR
using `anchore/sbom-action` (Syft). Runs independently of the build pipeline.

| Step | Detail |
|---|---|
| `flutter pub get` | Resolves transitive dependencies and writes `pubspec.lock`, which Syft reads to enumerate all packages |
| `anchore/sbom-action@v0` | Scans `src/` directory; emits `sbom.cdx.json` in CycloneDX JSON format |
| Artifact | Uploaded as `sbom-cyclonedx.json` on every run; downloadable from the Actions summary |

The SBOM covers all direct and transitive pub packages with their exact resolved
versions. It is not committed to the repository — it is regenerated from
`pubspec.lock` on every CI run.

---

## Adding a new Drift table

1. Create `core/database/tables/<name>_table.dart` — extend `Table`.
2. Add it to the `@DriftDatabase(tables: [...])` list in `app_database.dart`.
3. Create `core/database/daos/<name>_dao.dart` — annotate with `@DriftAccessor`.
4. Add the DAO to `@DriftDatabase(daos: [...])` and as a getter in `AppDatabase`.
5. Run `dart run build_runner build`.
6. Bump `schemaVersion` in `AppDatabase` and add a migration in `onUpgrade`.

---

## External API integrations

| Service | Endpoint | Auth | Notes |
|---|---|---|---|
| Yahoo Finance | `query2.finance.yahoo.com/v8/finance/chart/{symbol}` | None | Unofficial; rate-limited |
| Open Exchange Rates | `openexchangerates.org/api/latest.json` | App ID (free tier) | USD base only on free tier |
| OpenFIGI | `api.openfigi.com/v3/mapping` | None (basic) | ISIN → ticker/name/exchange/currency |
| Nextcloud | WebDAV (`/remote.php/dav/files/…`) | Basic auth | Self-signed cert support via fingerprint pinning |
| Anthropic Claude | `api.anthropic.com/v1/messages` | `x-api-key` header | SSE streaming; prompt caching on system block; stored in `settings.claude_api_key` |
| Groq | `api.groq.com/openai/v1/chat/completions` | Bearer token | OpenAI-compatible SSE; free tier; stored in `settings.groq_api_key` |
| Google Gemini | `generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent` | API key query param | SSE with `?alt=sse`; free tier (1M tokens/day); stored in `settings.gemini_api_key` |
