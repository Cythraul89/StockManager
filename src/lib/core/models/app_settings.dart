import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

import 'chart_range.dart';

enum AppTheme { system, light, dark }

enum MarketDataProvider { yahoo, finnhub }

class AppSettings extends Equatable {
  const AppSettings({
    required this.preferredCurrency,
    this.nextcloudUrl,
    this.nextcloudUsername,
    this.nextcloudPassword,
    this.nextcloudCertFingerprint,
    required this.nextcloudPath,
    required this.theme,
    required this.notificationsEnabled,
    required this.priceAlertThresholdPct,
    required this.dividendAlertDays,
    this.lastSyncAt,
    required this.nextcloudKeepExports,
    required this.sparklineRange,
    required this.marketDataProvider,
    this.finnhubApiKey,
    this.claudeApiKey,
  });

  final String preferredCurrency;
  final String? nextcloudUrl;
  final String? nextcloudUsername;
  final String? nextcloudPassword;
  final String? nextcloudCertFingerprint;
  final String nextcloudPath;
  final AppTheme theme;
  final bool notificationsEnabled;
  final Decimal priceAlertThresholdPct;
  final int dividendAlertDays;
  final DateTime? lastSyncAt;
  final int nextcloudKeepExports;
  final ChartRange sparklineRange;
  final MarketDataProvider marketDataProvider;
  final String? finnhubApiKey;
  final String? claudeApiKey;

  static AppSettings get defaults => AppSettings(
        preferredCurrency: 'EUR',
        nextcloudPath: '/StockManager/',
        theme: AppTheme.system,
        notificationsEnabled: true,
        priceAlertThresholdPct: Decimal.fromInt(5),
        dividendAlertDays: 3,
        nextcloudKeepExports: 5,
        sparklineRange: ChartRange.oneMonth,
        marketDataProvider: MarketDataProvider.yahoo,
      );

  AppSettings copyWith({
    String? preferredCurrency,
    String? nextcloudUrl,
    String? nextcloudUsername,
    String? nextcloudPassword,
    String? nextcloudCertFingerprint,
    String? nextcloudPath,
    AppTheme? theme,
    bool? notificationsEnabled,
    Decimal? priceAlertThresholdPct,
    int? dividendAlertDays,
    DateTime? lastSyncAt,
    int? nextcloudKeepExports,
    ChartRange? sparklineRange,
    MarketDataProvider? marketDataProvider,
    String? finnhubApiKey,
    String? claudeApiKey,
  }) =>
      AppSettings(
        preferredCurrency: preferredCurrency ?? this.preferredCurrency,
        nextcloudUrl: nextcloudUrl ?? this.nextcloudUrl,
        nextcloudUsername: nextcloudUsername ?? this.nextcloudUsername,
        nextcloudPassword: nextcloudPassword ?? this.nextcloudPassword,
        nextcloudCertFingerprint: nextcloudCertFingerprint ?? this.nextcloudCertFingerprint,
        nextcloudPath: nextcloudPath ?? this.nextcloudPath,
        theme: theme ?? this.theme,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        priceAlertThresholdPct:
            priceAlertThresholdPct ?? this.priceAlertThresholdPct,
        dividendAlertDays: dividendAlertDays ?? this.dividendAlertDays,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        nextcloudKeepExports: nextcloudKeepExports ?? this.nextcloudKeepExports,
        sparklineRange: sparklineRange ?? this.sparklineRange,
        marketDataProvider: marketDataProvider ?? this.marketDataProvider,
        finnhubApiKey: finnhubApiKey ?? this.finnhubApiKey,
        claudeApiKey: claudeApiKey ?? this.claudeApiKey,
      );

  @override
  List<Object?> get props => [
        preferredCurrency,
        nextcloudUrl,
        nextcloudUsername,
        nextcloudPassword,
        nextcloudCertFingerprint,
        nextcloudPath,
        theme,
        notificationsEnabled,
        priceAlertThresholdPct,
        dividendAlertDays,
        lastSyncAt,
        nextcloudKeepExports,
        sparklineRange,
        marketDataProvider,
        finnhubApiKey,
        claudeApiKey,
      ];
}
