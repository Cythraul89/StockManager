# StockManager — Requirements

## 1. Overview

StockManager is a cross-platform portfolio tracking application for managing stocks held across multiple brokers. It provides real-time valuations, tracks buy/sell transactions and dividends, and synchronises all data with a Nextcloud instance in a spreadsheet format.

---

## 2. Brokers

- The app supports **up to 10 brokers**.
- Brokers can be added, edited, and removed within the app.
- Each broker has at minimum: name, optional notes/description.

---

## 3. Stocks

- Up to **100 different stocks** can be managed across all brokers.
- Each stock is associated with one broker.
- Each stock is identified by its **ISIN** (International Securities Identification Number).
- The stock name, ticker symbol, exchange, and currency are **automatically resolved** from the ISIN via a lookup service when adding a stock; the user does not need to enter these manually.
- Resolved fields can be reviewed and corrected by the user before saving.
- Stocks can be held in **different currencies**.
- Stocks can be added and removed in the app.

### 3.1 Transactions

- For each stock, the user can record **executed buy and sell transactions**.
- Each transaction records at minimum:
  - Transaction type (buy / sell)
  - Date and time of execution
  - Number of shares / units
  - Price per share at execution
  - Currency
  - Optional: fees/commission, notes

### 3.2 Stock Splits

- The user can record **stock splits and reverse splits** for any stock, including:
  - Date of the split
  - Split ratio (e.g. 4:1 or 1:10)
- All historical transaction prices and share counts are automatically adjusted to reflect splits, keeping the cost-basis accurate.

### 3.3 Average Position Price

- The app automatically calculates the **weighted average buy price** per stock from all recorded transactions.
- This is updated in real-time as new buy/sell transactions are added.

### 3.4 Realised and Unrealised P&L

- **Unrealised P&L**: difference between current market value and cost-basis for open positions.
- **Realised P&L**: profit or loss locked in from completed sell transactions.
- Both are shown per stock and as a portfolio total, in the preferred display currency.

---

## 4. Portfolio Overview

### 4.1 Total Portfolio Value

- Display the **total current value** of the entire portfolio.
- Aggregate values across all brokers and all currencies (with currency conversion).

### 4.2 Individual Stock Value

- Display the **current value per stock** (units × live price).
- Show the currency of each stock.

### 4.3 Live Market Data

- Current prices are fetched in **real-time from the Internet** (e.g. via a public market data API).
- Live data is used solely for display; the app functions without it (see Section 7).

### 4.4 Buy Price Overview

- Display the **total invested amount** across the portfolio.
- Display the **invested amount per stock** (sum of buy transactions minus sell proceeds).

### 4.5 Preferred Display Currency

- The user can select a **preferred display currency** in the app settings.
- The dashboard and all portfolio totals convert and display every value in this single currency using live (or last-known) exchange rates.
- Individual stock views still show the stock's native currency alongside the converted value.
- The user can set a **manual exchange rate override** per currency pair for use when offline or when the live rate is considered unreliable.

### 4.6 Dividends

- For each stock the user can record **paid-out dividends**, including:
  - Payment date
  - Amount per share
  - Total amount received
  - Currency
  - Optional: withholding tax, notes
- The app displays **expected (upcoming) dividends** per stock, including:
  - Expected payment date
  - Estimated total based on current holdings
- A dividend overview shows:
  - Total dividends received (all-time and per year), converted to the preferred display currency
  - Upcoming expected dividends with dates and estimated totals
- Each stock has an optional **Dividend Reinvestment (DRIP)** flag; when enabled, recorded dividend payments automatically generate a corresponding buy transaction for that stock.
- Each stock displays its **annual dividend yield** (annual dividend per share ÷ current price × 100).

---

## 5. Data Synchronisation — Nextcloud

- All portfolio data is **synchronised with a user-configured Nextcloud instance**.
- Synchronisation is triggered manually and/or automatically when a network connection is available.
- The app supports Nextcloud instances that use **self-signed TLS certificates**; the user can explicitly accept and pin a server certificate during initial setup.
- The data file stored on Nextcloud is an **ODS (OpenDocument Spreadsheet)** file that is human-readable and can be opened in any ODS-compatible office suite (e.g. LibreOffice Calc, OnlyOffice Spreadsheets).
- The ODS file contains structured sheets for: brokers, stocks, full transaction history, dividends (paid and expected), and a summary of current valuations.
- Each export is **timestamped** (filename or internal metadata) so the user can see when the last sync occurred.
- Conflict handling: the app's local data is treated as the source of truth; the cloud copy is the export target.

---

## 6. Supported Platforms

| Platform | Minimum Version |
|---|---|
| Android | Android 13 |
| macOS | macOS 15 |
| Ubuntu | Ubuntu 24.04 |
| Windows | Windows 11 |

- The Android build is a native mobile application.
- The PC builds (macOS, Ubuntu, Windows) share a common desktop codebase.

---

## 7. Offline Support

- The app **must be fully functional without an Internet connection**, with the following exceptions:
  - Live market prices require an active Internet connection; when offline, the last known prices (with a timestamp) are displayed instead.
  - Nextcloud synchronisation requires an active network connection to the Nextcloud server.
- All portfolio data (brokers, stocks, transactions, historical prices) is stored **locally on the device**.

---

## 8. Notifications and Alerts

### 8.1 Local Notifications
- The app sends **local notifications** (no external server required) for:
  - An approaching expected dividend payment date (configurable lead time, e.g. 3 days before)
  - A stock price rising or falling by a user-defined percentage threshold
- Notifications are optional and individually configurable per stock.

### 8.2 Push Notifications (Android only)
- **Android only**: the app receives **push notifications** via Firebase Cloud Messaging (FCM) for stock-related events even when the app is not open, including:
  - Significant price movements (user-defined threshold per stock)
  - Dividend payment confirmations
  - Expected dividend dates approaching
- Push notifications require an active Internet connection.
- The user can enable or disable push notifications globally and per stock.
- Desktop platforms (macOS, Windows, Ubuntu) use local notifications only (Section 8.1); no background push service is required on desktop.

---

## 9. Non-Functional Requirements

- **Privacy**: all data remains on the user's own device and their own Nextcloud; no third-party cloud storage.
- **Responsive / adaptive UI**: the app uses a single adaptive layout that adjusts to screen size:
  - **Android**: single-column navigation, bottom navigation bar, touch-optimised controls.
  - **Desktop** (macOS, Windows, Ubuntu): multi-column layout making use of the available screen space — e.g. a persistent sidebar for navigation, a master-detail split for stock lists and detail views, and wider dashboard panels showing more data at once without scrolling.
- **Dark mode**: the app supports light and dark themes on all platforms, following the system preference by default.
- **Performance**: the app must load the portfolio overview within 2 seconds on a modern device (offline data only).
- **Data integrity**: transactions and portfolio data must not be lost during sync or app updates.

---

## 10. Planned Features

Features confirmed for a future version. Not in scope for the initial release.

### 10.1 Analyst Target Price and Rating
- Each stock detail view displays the **consensus analyst target price** (fetched from market data) alongside the current price.
- The **distance to target** is shown as a percentage (e.g. +18% upside).
- The **analyst consensus rating** (Buy / Hold / Sell) is shown per stock, including the number of analysts contributing to the consensus.

### 10.2 Trailing Stop-Loss Notification
- The user can set a **trailing stop-loss threshold** per stock (e.g. −10%).
- The threshold tracks the stock's highest recorded price since the alert was enabled.
- A notification is triggered when the current price falls more than the threshold percentage below that peak.
- The trailing high-water mark is updated automatically as the price rises.
- Configurable per stock; displayed alongside the current price on the stock detail screen.

### 10.3 Watchlist (Monitoring-Only Stocks)
- Stocks can be added in **monitoring mode** — no broker assignment, no transactions required.
- Watchlist stocks appear in a dedicated section separate from held positions.
- All live price, target price, rating, and news features apply to watchlist stocks.
- A watchlist stock can be promoted to a held position at any time by assigning a broker and adding a transaction.

### 10.4 Price History Chart
- Each stock detail view includes a **price history chart** showing closing prices over selectable time ranges (1W, 1M, 3M, 1Y, 5Y).
- The chart highlights the user's buy and sell transactions as overlaid markers.
- The dashboard shows a **mini sparkline** per stock in the stock list.
- Charts are rendered from cached historical data and work offline for the last fetched range.

### 10.5 Stock News
- Each stock detail view includes a **news feed** of recent articles related to that stock.
- News is fetched from a public financial news API (e.g. Finnhub free tier) using the stock's ticker symbol.
- Articles open in the device's default browser.
- News requires an Internet connection; a “no connection” placeholder is shown offline.
