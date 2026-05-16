# StockManager — Class Diagram

> Generated from source. Arrows: `-->` association, `..>` dependency, `*--` composition.

```mermaid
classDiagram
    %% ─────────────────────────────────────────────────────────
    %% DOMAIN MODELS
    %% ─────────────────────────────────────────────────────────

    class Broker {
        +String id
        +String name
        +String? notes
        +copyWith() Broker
    }

    class Stock {
        +String id
        +String? brokerId
        +String isin
        +String symbol
        +String name
        +String exchange
        +String currency
        +bool dripEnabled
        +copyWith() Stock
    }

    class StockTransaction {
        +String id
        +String stockId
        +TransactionType type
        +DateTime executedAt
        +Decimal shares
        +Decimal pricePerShare
        +String currency
        +Decimal fees
        +String? notes
        +totalCost() Decimal
        +copyWith() StockTransaction
    }

    class TransactionType {
        <<enumeration>>
        buy
        sell
    }

    class StockSplit {
        +String id
        +String stockId
        +DateTime date
        +int fromShares
        +int toShares
        +ratio() Decimal
    }

    class Dividend {
        +String id
        +String stockId
        +DividendType type
        +DateTime date
        +Decimal amountPerShare
        +Decimal? totalAmount
        +String currency
        +Decimal? withholdingTax
        +String? notes
        +DividendSource source
        +bool confirmed
        +isPendingConfirmation() bool
        +netAmount() Decimal
        +copyWith() Dividend
    }

    class DividendType {
        <<enumeration>>
        paid
        expected
    }

    class DividendSource {
        <<enumeration>>
        manual
        auto
    }

    class FetchedDividend {
        +DateTime date
        +Decimal amountPerShare
        +bool isPaid
    }

    class PricePoint {
        +DateTime date
        +Decimal price
        +String currency
    }

    class ChartRange {
        <<enumeration>>
        oneDay
        oneWeek
        oneMonth
        sixMonths
        oneYear
        fiveYears
        max
        +String label
        +String yahooRange
        +String yahooInterval
    }

    class AnalystData {
        +Decimal targetMeanPrice
        +Decimal? targetLowPrice
        +Decimal? targetHighPrice
        +String? recommendationKey
        +int? numberOfAnalysts
        +String? financialCurrency
        +int? strongBuyCount
        +int? buyCount
        +int? holdCount
        +int? sellCount
        +int? strongSellCount
        +Decimal? fiftyTwoWeekLow
        +Decimal? fiftyTwoWeekHigh
        +Decimal? trailingPE
        +Decimal? forwardPE
        +Decimal? trailingEps
        +Decimal? yearChangePct
        +copyWith() AnalystData
    }

    class PriceQuote {
        +String stockId
        +Decimal price
        +String currency
        +DateTime fetchedAt
        +bool isManualOverride
        +Decimal? dayChangePct
        +withStaleness() PriceQuote
    }

    class ExchangeRate {
        +String base
        +String target
        +Decimal rate
        +DateTime fetchedAt
        +bool isManualOverride
        +isStale() bool
        +convert(Decimal amount) Decimal
        +find(rates, from, to) ExchangeRate?$
    }

    class AppSettings {
        +String preferredCurrency
        +String? nextcloudUrl
        +String? nextcloudUsername
        +String nextcloudPath
        +int nextcloudKeepExports
        +AppTheme theme
        +bool notificationsEnabled
        +Decimal priceAlertThresholdPct
        +int dividendAlertDays
        +DateTime? lastSyncAt
        +ChartRange sparklineRange
        +copyWith() AppSettings
        +defaults AppSettings$
    }

    class AppTheme {
        <<enumeration>>
        system
        light
        dark
    }

    %% Domain associations
    Stock "many" --> "0..1" Broker : belongs to
    StockTransaction "many" --> "1" Stock : belongs to
    StockTransaction --> TransactionType
    StockSplit "many" --> "1" Stock : belongs to
    Dividend "many" --> "1" Stock : belongs to
    Dividend --> DividendType
    Dividend --> DividendSource
    PriceQuote --> Stock : cached for
    AppSettings --> AppTheme
    AppSettings --> ChartRange : sparklineRange

    %% ─────────────────────────────────────────────────────────
    %% CALCULATORS
    %% ─────────────────────────────────────────────────────────

    class PortfolioCalculator {
        +calculate(txs, splits) PositionSummary$
        +sharesAtDate(txs, splits, asOf) Decimal$
        +splitMultiplierAfter(txDate, splits) Decimal$
    }

    class PositionSummary {
        +Decimal sharesHeld
        +Decimal avgBuyPrice
        +Decimal totalInvested
    }

    class PnlCalculator {
        +calculate(txs, splits, currentPrice) PnlResult$
        +convert(result, rate) PnlResult$
    }

    class PnlResult {
        +Decimal unrealisedPnl
        +Decimal unrealisedPnlPct
        +Decimal realisedPnl
        +Decimal currentValue
        +Decimal totalInvested
    }

    class DividendCalculator {
        +calculate(dividends, price, shares) DividendSummary
        +convert(summary, rate) DividendSummary
        +estimatedTotal() Decimal
    }

    class DividendSummary {
        +Decimal allTimeTotal
        +Decimal currentYearTotal
        +Decimal annualYieldPct
    }

    %% Calculator dependencies and outputs
    PortfolioCalculator ..> StockTransaction : consumes
    PortfolioCalculator ..> StockSplit : consumes
    PortfolioCalculator --> PositionSummary : produces

    PnlCalculator ..> StockTransaction : consumes
    PnlCalculator ..> StockSplit : consumes
    PnlCalculator ..> PriceQuote : consumes
    PnlCalculator ..> ExchangeRate : converts via
    PnlCalculator --> PnlResult : produces

    DividendCalculator ..> Dividend : consumes
    DividendCalculator ..> ExchangeRate : converts via
    DividendCalculator --> DividendSummary : produces

    %% ─────────────────────────────────────────────────────────
    %% SERVICES
    %% ─────────────────────────────────────────────────────────

    class MarketDataService {
        +fetchQuote(symbol, stockId) PriceQuote?
        +fetchQuotes(symbolMap) Map
        +fetchHistoricalPrice(symbol, date) Decimal?
        +fetchPriceHistory(symbol, range) List~PricePoint~
        +fetchDividends(symbol) List~FetchedDividend~
        +fetchAnalystData(symbol) AnalystData?
    }

    class CurrencyService {
        +fetchRates(baseCurrency) List~ExchangeRate~
    }

    class IsinLookupService {
        +lookup(isin) IsinLookupResult
    }

    class IsinLookupResult {
        +String symbol
        +String name
        +String exchange
        +String currency
    }

    class NotificationService {
        +initialize()
        +showPriceAlert(stock, quote)
        +showDividendAlert(stock, dividend)
        +cancelAll()
    }

    class NextcloudService {
        +verifyCredentials(url, user, pw) Future
        +uploadBackup(url, user, pw, path, bytes) Future
        +upload(url, user, pw, path, bytes, contentType) Future
        +listFiles(url, user, pw, path) List~String~
        +delete(url, user, pw, path) Future
        +downloadFile(url, user, pw, path) Uint8List
        +findLatestBackup(url, user, pw, path) RemoteBackupInfo?
        +fetchCertificateInfo(url) CertificateInfo?
        +pinCertificate(fingerprint) Future
        +unpinCertificate() Future
        +getPinnedFingerprint() String?
    }

    class RemoteBackupInfo {
        +String remotePath
        +DateTime backupDate
    }

    class CertificateInfo {
        +String fingerprint
        +String subject
        +String issuer
        +DateTime validUntil
    }

    class BackupService {
        +exportToZip() File
        +exportToOds() File
        +importFromBytes(bytes) Future
    }

    class SyncStatus {
        <<enumeration>>
        idle
        syncing
        error
    }

    class NextcloudSyncState {
        +SyncStatus status
        +DateTime? lastSyncAt
        +String? error
        +RemoteBackupInfo? pendingRestore
        +copyWith() NextcloudSyncState
    }

    class NextcloudSyncNotifier {
        +syncNow() Future
        +scheduleSync()
        +checkForRemoteBackup() Future
        +restoreFromRemote() Future
        +dismissRestore()
    }

    NextcloudSyncNotifier --> NextcloudSyncState : manages
    NextcloudSyncState --> RemoteBackupInfo
    NextcloudSyncState --> SyncStatus
    NextcloudService --> RemoteBackupInfo : produces
    NextcloudService --> CertificateInfo : produces
    BackupService ..> AppDatabase : reads/writes

    %% Service outputs
    MarketDataService --> PriceQuote : produces
    MarketDataService --> PricePoint : produces
    MarketDataService --> FetchedDividend : produces
    MarketDataService --> AnalystData : produces
    MarketDataService ..> ChartRange : parameterised by
    CurrencyService --> ExchangeRate : produces
    IsinLookupService --> IsinLookupResult : produces
    NotificationService ..> Stock : alerts on
    NotificationService ..> PriceQuote : alerts on
    NotificationService ..> Dividend : alerts on

    %% ─────────────────────────────────────────────────────────
    %% DATABASE LAYER
    %% ─────────────────────────────────────────────────────────

    class AppDatabase {
        +schemaVersion = 4
        +brokersDao BrokersDao
        +stocksDao StocksDao
        +transactionsDao TransactionsDao
        +dividendsDao DividendsDao
        +settingsDao SettingsDao
        +forTesting(executor)$ AppDatabase
    }

    class BrokersDao {
        +watchAll() Stream~List~Broker~~
        +getAll() Future~List~Broker~~
        +findById(id) Future~Broker~~
        +upsert(broker) Future
        +deleteById(id) Future
        +count() Future~int~
    }

    class StocksDao {
        +watchAll() Stream~List~Stock~~
        +watchById(id) Stream~Stock~~
        +getAll() Future~List~Stock~~
        +findById(id) Future~Stock~~
        +findByIsin(isin) Future~Stock~~
        +upsert(stock) Future
        +deleteById(id) Future
        +getCachedPrice(id) Future~PriceQuote~~
        +getAllCachedPrices() Future~List~PriceQuote~~
        +upsertPrice(quote) Future
        +watchSplitsForStock(id) Stream~List~StockSplit~~
        +getSplitsForStock(id) Future~List~StockSplit~~
        +upsertSplit(split) Future
        +deleteSplit(id) Future
    }

    class TransactionsDao {
        +watchByStock(id) Stream~List~StockTransaction~~
        +getByStock(id) Future~List~StockTransaction~~
        +getAll() Future~List~StockTransaction~~
        +findById(id) Future~StockTransaction~~
        +insert(tx) Future
        +updateRow(tx) Future
        +deleteById(id) Future
    }

    class DividendsDao {
        +watchByStock(id) Stream~List~Dividend~~
        +getByStock(id) Future~List~Dividend~~
        +getPaid() Future~List~Dividend~~
        +getExpected() Future~List~Dividend~~
        +getAll() Future~List~Dividend~~
        +findById(id) Future~DividendRow~~
        +findByStockAndDate(stockId, date) Future~DividendRow~~
        +insert(div) Future
        +updateRow(div) Future
        +deleteById(id) Future
    }

    class SettingsDao {
        +watchSettings() Stream~AppSettings~
        +getSettings() Future~AppSettings~
        +upsertSettings(settings) Future
        +watchExchangeRates() Stream~List~ExchangeRate~~
        +getExchangeRates() Future~List~ExchangeRate~~
        +getRate(base, target) Future~ExchangeRate~~
        +upsertRate(rate) Future
        +deleteRate(base, target) Future
    }

    %% Database composition
    AppDatabase *-- BrokersDao
    AppDatabase *-- StocksDao
    AppDatabase *-- TransactionsDao
    AppDatabase *-- DividendsDao
    AppDatabase *-- SettingsDao

    %% DAO → domain model mapping
    BrokersDao ..> Broker : maps rows to
    StocksDao ..> Stock : maps rows to
    StocksDao ..> PriceQuote : maps rows to
    StocksDao ..> StockSplit : maps rows to
    TransactionsDao ..> StockTransaction : maps rows to
    DividendsDao ..> Dividend : maps rows to
    SettingsDao ..> AppSettings : maps rows to
    SettingsDao ..> ExchangeRate : maps rows to
```

---

## Riverpod Provider Graph

```
databaseProvider ──────────────────────────────────────────────┐
                                                                │
brokersStreamProvider ←── BrokersDao.watchAll()                │
stocksStreamProvider  ←── StocksDao.watchAll()                 │
stocksProvider        ←── StocksDao.getAll()                   ├── AppDatabase
transactionsByStock   ←── TransactionsDao.watchByStock(id)     │
dividendsByStock      ←── DividendsDao.watchByStock(id)        │
allDividendsProvider  ←── DividendsDao.getAll()                │
settingsStreamProvider←── SettingsDao.watchSettings()          │
exchangeRatesProvider ←── SettingsDao.watchExchangeRates()     │
splitsByStockProvider ←── StocksDao.watchSplitsForStock(id)    │
                                                                ┘

priceQuotesProvider  ← StateProvider (in-memory, refreshed on demand)

priceHistoryProvider(stockId, range)  (FutureProvider.family, keepAlive 5 min)
  ├── stockByIdProvider(stockId)  ← re-fetches when symbol changes
  └── marketDataServiceProvider → MarketDataService.fetchPriceHistory()

portfolioSummaryProvider (FutureProvider)
  ├── stocksProvider
  ├── brokersProvider
  ├── settingsProvider
  ├── exchangeRatesProvider
  ├── priceQuotesProvider
  ├── transactionsByStockProvider (per stock)
  ├── splitsByStockProvider      (per stock)
  └── dividendsByStockProvider   (per stock)
       │
       ├── PortfolioCalculator.calculate()
       ├── PnlCalculator.calculate()  ← price converted quoteCurrency→stock.currency first
       ├── PnlCalculator.convert()    ← then stock.currency→preferredCurrency
       └── DividendCalculator.calculate() + convert()

allDividendsProvider (FutureProvider)
  ├── databaseProvider → DividendsDao.getAll()
  └── dataVersionProvider  ← invalidated on any write; triggers re-fetch

stockActionsProvider  ─── StockActions  (addStock, updateStock, deleteStock,
                                         addTransaction, updateTransaction, deleteTransaction,
                                         addDividend, updateDividend, deleteDividend,
                                         syncDividends, confirmDividend,
                                         setManualPrice, clearManualPrice, cacheMarketPrice,
                                         loadManualPrices)

settingsActionsProvider ─ SettingsActions (saveSettings, setManualRate,
                                           deleteRate, cacheRates)

backupServiceProvider  ── BackupService (exportToZip, exportToOds,
                                         importFromBytes)

nextcloudSyncProvider (NotifierProvider)
  ├── settingsProvider          (credentials, lastSyncAt, nextcloudPath, nextcloudKeepExports)
  ├── nextcloudServiceProvider  (WebDAV upload / download / PROPFIND / delete)
  ├── backupServiceProvider     (exportToZip, importFromBytes)
  ├── dataVersionProvider       (listens → schedules debounced sync)
  └── NextcloudSyncState
        ├── status: SyncStatus  (idle | syncing | error)
        ├── lastSyncAt: DateTime?
        ├── error: String?
        └── pendingRestore: RemoteBackupInfo?

analystRefreshProvider(stockId)  (StateProvider.family&lt;int, String&gt;)
  └── incremented by the refresh button on StockDetailScreen

analystDataProvider(stockId)  (FutureProvider.family, keepAlive 10 min)
  ├── analystRefreshProvider(stockId)  ← re-fetches on increment
  └── marketDataServiceProvider → MarketDataService.fetchAnalystData()

isinLookupServiceProvider  ── IsinLookupService  (must be overridden in ProviderScope)
  └── used by AddStockScreen and EditStockScreen (ISIN lookup / Research button)
```

---

## Navigation Tree

```
ShellRoute (AdaptiveShell)
│
├── /                              DashboardScreen
│
├── /stocks                        StocksScreen
│   ├── /stocks/add                AddStockScreen
│   └── /stocks/:id                StockDetailScreen
│       ├── /stocks/:id/edit                          EditStockScreen
│       ├── /stocks/:id/transactions/add              AddTransactionScreen
│       ├── /stocks/:id/transactions/:txId/edit       EditTransactionScreen
│       ├── /stocks/:id/dividends/add                 AddDividendScreen
│       └── /stocks/:id/dividends/:divId/edit         EditDividendScreen
│
├── /dividends                     DividendsScreen
│
├── /brokers                       BrokersScreen
│   ├── /brokers/add               AddBrokerScreen
│   └── /brokers/:id/edit          EditBrokerScreen
│
└── /settings                      SettingsScreen
    ├── /settings/nextcloud        NextcloudSettingsScreen
    ├── /settings/currency         CurrencySettingsScreen
    └── /settings/notifications    NotificationSettingsScreen
```