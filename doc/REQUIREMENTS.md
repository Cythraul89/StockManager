# StockManager — Requirements

## 1. Overview

StockManager is a cross-platform portfolio tracking application for managing stocks held across multiple brokers. It provides real-time valuations, tracks buy/sell transactions, and synchronises all data with a Nextcloud instance in a human-readable format.

---

## 2. Brokers

- The app supports **up to 10 brokers**.
- Brokers can be added, edited, and removed within the app.
- Each broker has at minimum: name, optional notes/description.

---

## 3. Stocks

- Up to **100 different stocks** can be managed across all brokers.
- Each stock is associated with one broker.
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

---

## 5. Data Synchronisation — Nextcloud

- All portfolio data is **synchronised with a user-configured Nextcloud instance**.
- Synchronisation is triggered manually and/or automatically when a network connection is available.
- The data file stored on Nextcloud is an **ODT (OpenDocument Text) document** that is human-readable and can be opened in any ODT-compatible office suite (e.g. LibreOffice, OnlyOffice).
- The ODT document contains a formatted summary of brokers, stocks, transactions, and current valuations.
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

## 8. Non-Functional Requirements

- **Privacy**: all data remains on the user's own device and their own Nextcloud; no third-party cloud storage.
- **Usability**: the UI must be usable on both small mobile screens (Android) and large desktop displays.
- **Performance**: the app must load the portfolio overview within 2 seconds on a modern device (offline data only).
- **Data integrity**: transactions and portfolio data must not be lost during sync or app updates.
