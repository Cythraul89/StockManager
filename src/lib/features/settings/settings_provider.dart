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

final nextcloudServiceProvider = Provider<NextcloudService>((ref) {
  return NextcloudService(ref.watch(secureStorageProvider));
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
  const SettingsActions(this._db);
  final AppDatabase _db;

  // Targeted update — avoids reading the full settings row first, so it
  // cannot accidentally overwrite other columns with stale provider data.
  Future<void> saveLastSyncAt(DateTime time) =>
      _db.settingsDao.updateLastSyncAt(time);

  Future<void> saveSettings(AppSettings s) => _db.settingsDao.upsertSettings(
        SettingsCompanion(
          preferredCurrency: Value(s.preferredCurrency),
          nextcloudUrl: Value(s.nextcloudUrl),
          nextcloudUsername: Value(s.nextcloudUsername),
          nextcloudPath: Value(s.nextcloudPath),
          theme: Value(s.theme.name),
          notificationsEnabled: Value(s.notificationsEnabled),
          priceAlertThresholdPct: Value(s.priceAlertThresholdPct),
          dividendAlertDays: Value(s.dividendAlertDays),
          lastSyncAt: Value(s.lastSyncAt),
          nextcloudKeepExports: Value(s.nextcloudKeepExports),
          sparklineRange: Value(s.sparklineRange.label),
        ),
      );

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
  return SettingsActions(ref.watch(databaseProvider));
});

// ── Row → model mappers ────────────────────────────────────────────────────────────────────────────────────────

AppSettings _settingsFromRow(SettingsRow r) => AppSettings(
      preferredCurrency: r.preferredCurrency,
      nextcloudUrl: r.nextcloudUrl,
      nextcloudUsername: r.nextcloudUsername,
      nextcloudPath: r.nextcloudPath,
      theme: _themeFromString(r.theme),
      notificationsEnabled: r.notificationsEnabled,
      priceAlertThresholdPct: r.priceAlertThresholdPct,
      dividendAlertDays: r.dividendAlertDays,
      lastSyncAt: r.lastSyncAt,
      nextcloudKeepExports: r.nextcloudKeepExports,
      sparklineRange: _chartRangeFromLabel(r.sparklineRange),
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
