import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/database/app_database.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/chart_range.dart';
import '../../core/models/exchange_rate.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/currency_service.dart';
import '../../core/services/nextcloud_service.dart';
import '../../core/services/notification_service.dart';
import '../stocks/stocks_provider.dart';

// ── Core service providers ────────────────────────────────────────────────────────────────────────────────────────

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

/// Reads the Finnhub API key from the settings table.
final finnhubApiKeyProvider = FutureProvider<String?>((ref) async {
  final row = await ref.watch(databaseProvider).settingsDao.getSettings();
  return row?.finnhubApiKey;
});

/// Reads the Claude API key from the settings table.
final claudeApiKeyProvider = FutureProvider<String?>((ref) async {
  final row = await ref.watch(databaseProvider).settingsDao.getSettings();
  return row?.claudeApiKey;
});

/// Increment to bust all cached analyst data (provider switch or key change).
final analystCacheVersionProvider = StateProvider<int>((ref) => 0);

final nextcloudServiceProvider = Provider<NextcloudService>((ref) {
  return const NextcloudService();
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(databaseProvider));
});

final currencyServiceProvider = Provider<CurrencyService>((ref) {
  throw UnimplementedError('currencyServiceProvider must be overridden');
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  throw UnimplementedError('notificationServiceProvider must be overridden');
});

// ── Settings providers ───────────────────────────────────────────────────────────────────────────────────────

final settingsProvider = FutureProvider<AppSettings>((ref) async {
  final db = ref.watch(databaseProvider);
  final row = await db.settingsDao.getSettings();
  return row == null ? AppSettings.defaults : _settingsFromRow(row);
});

final settingsStreamProvider = StreamProvider<AppSettings>((ref) {
  final db = ref.watch(databaseProvider);
  return db.settingsDao
      .watchSettings()
      .map((row) => row == null ? AppSettings.defaults : _settingsFromRow(row));
});

// ── Exchange rate providers ──────────────────────────────────────────────────────────────────────────────────────

final exchangeRatesProvider = StreamProvider<List<ExchangeRate>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.settingsDao
      .watchExchangeRates()
      .map((rows) => rows.map(_rateFromRow).toList());
});

// ── Settings actions ──────────────────────────────────────────────────────────────────────────────────────────

class SettingsActions {
  const SettingsActions(this._db, this._ref);
  final AppDatabase _db;
  final Ref _ref;

  // Targeted update — avoids reading the full settings row first, so it
  // cannot accidentally overwrite other columns with stale provider data.
  Future<void> saveLastSyncAt(DateTime time) =>
      _db.settingsDao.updateLastSyncAt(time);

  Future<void> saveSettings(AppSettings s) async {
    final current = _ref.read(settingsStreamProvider).value;
    if (current != null && current.marketDataProvider != s.marketDataProvider) {
      _ref.read(analystCacheVersionProvider.notifier).update((v) => v + 1);
    }
    await _db.settingsDao.upsertSettings(
      SettingsCompanion(
        preferredCurrency: Value(s.preferredCurrency),
        nextcloudUrl: Value(s.nextcloudUrl),
        nextcloudUsername: Value(s.nextcloudUsername),
        nextcloudPassword: Value(s.nextcloudPassword?.isEmpty == true ? null : s.nextcloudPassword),
        nextcloudPath: Value(s.nextcloudPath),
        theme: Value(s.theme.name),
        notificationsEnabled: Value(s.notificationsEnabled),
        priceAlertThresholdPct: Value(s.priceAlertThresholdPct),
        dividendAlertDays: Value(s.dividendAlertDays),
        lastSyncAt: Value(s.lastSyncAt),
        nextcloudKeepExports: Value(s.nextcloudKeepExports),
        sparklineRange: Value(s.sparklineRange.label),
        marketDataProvider: Value(s.marketDataProvider == MarketDataProvider.finnhub ? 'finnhub' : 'yahoo'),
        // nextcloudCertFingerprint and finnhubApiKey are managed by their own
        // targeted update methods — absent here so upsert never overwrites them.
      ),
    );
  }

  Future<void> saveCertFingerprint(String? fingerprint) =>
      _db.settingsDao.updateCertFingerprint(fingerprint);

  Future<void> saveFinnhubApiKey(String? key) async {
    final trimmed = key?.trim();
    await _db.settingsDao
        .updateFinnhubApiKey(trimmed == null || trimmed.isEmpty ? null : trimmed);
    _ref.read(analystCacheVersionProvider.notifier).update((v) => v + 1);
    _ref.invalidate(finnhubApiKeyProvider);
  }

  Future<void> saveClaudeApiKey(String? key) async {
    final trimmed = key?.trim();
    await _db.settingsDao
        .updateClaudeApiKey(trimmed == null || trimmed.isEmpty ? null : trimmed);
    _ref.invalidate(claudeApiKeyProvider);
  }

  Future<void> setManualRate(String base, String target, Decimal rate) =>
      _db.settingsDao.upsertRate(
        ExchangeRateCacheCompanion.insert(
          base: base,
          target: target,
          rate: rate,
          fetchedAt: DateTime.now(),
          manualOverride: const Value(true),
        ),
      );

  Future<void> deleteRate(String base, String target) =>
      _db.settingsDao.deleteRate(base, target);

  Future<void> cacheRates(List<ExchangeRate> rates) async {
    for (final r in rates) {
      await _db.settingsDao.upsertRate(
        ExchangeRateCacheCompanion.insert(
          base: r.base,
          target: r.target,
          rate: r.rate,
          fetchedAt: r.fetchedAt,
          manualOverride: Value(r.isManualOverride),
        ),
      );
    }
  }
}

final settingsActionsProvider = Provider<SettingsActions>((ref) {
  return SettingsActions(ref.watch(databaseProvider), ref);
});

// ── Row → model mappers ────────────────────────────────────────────────────────────────────────────────────────

AppSettings _settingsFromRow(SettingsRow r) => AppSettings(
      preferredCurrency: r.preferredCurrency,
      nextcloudUrl: r.nextcloudUrl,
      nextcloudUsername: r.nextcloudUsername,
      nextcloudPassword: r.nextcloudPassword,
      nextcloudCertFingerprint: r.nextcloudCertFingerprint,
      nextcloudPath: r.nextcloudPath,
      theme: _themeFromString(r.theme),
      notificationsEnabled: r.notificationsEnabled,
      priceAlertThresholdPct: r.priceAlertThresholdPct,
      dividendAlertDays: r.dividendAlertDays,
      lastSyncAt: r.lastSyncAt,
      nextcloudKeepExports: r.nextcloudKeepExports,
      sparklineRange: _chartRangeFromLabel(r.sparklineRange),
      marketDataProvider: _marketDataProviderFromString(r.marketDataProvider),
      finnhubApiKey: r.finnhubApiKey,
      claudeApiKey: r.claudeApiKey,
    );

ExchangeRate _rateFromRow(ExchangeRateCacheRow r) => ExchangeRate(
      base: r.base,
      target: r.target,
      rate: r.rate,
      fetchedAt: r.fetchedAt,
      isManualOverride: r.manualOverride,
    );

AppTheme _themeFromString(String s) => switch (s) {
      'light' => AppTheme.light,
      'dark' => AppTheme.dark,
      _ => AppTheme.system,
    };

ChartRange _chartRangeFromLabel(String label) => ChartRange.values.firstWhere(
      (r) => r.label == label,
      orElse: () => ChartRange.oneMonth,
    );

MarketDataProvider _marketDataProviderFromString(String s) => switch (s) {
      'finnhub' => MarketDataProvider.finnhub,
      _ => MarketDataProvider.yahoo,
    };
