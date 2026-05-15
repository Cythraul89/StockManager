import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_manager/app.dart';
import 'package:stock_manager/core/database/app_database.dart';
import 'package:stock_manager/core/models/analyst_data.dart';
import 'package:stock_manager/core/models/fetched_dividend.dart';
import 'package:stock_manager/core/models/price_quote.dart';
import 'package:stock_manager/core/services/log_service.dart';
import 'package:stock_manager/core/services/market_data_service.dart';
import 'package:stock_manager/core/services/notification_service.dart';
import 'package:stock_manager/features/dashboard/dashboard_provider.dart';
import 'package:stock_manager/features/settings/nextcloud_sync_provider.dart';
import 'package:stock_manager/features/settings/settings_provider.dart';
import 'package:stock_manager/features/stocks/stocks_provider.dart';

class _NoOpSyncNotifier extends NextcloudSyncNotifier {
  @override
  NextcloudSyncState build() => const NextcloudSyncState();
}

class _NoOpMarketDataService extends MarketDataService {
  _NoOpMarketDataService() : super(Dio());
  @override
  Future<PriceQuote?> fetchQuote(String symbol, String stockId,
          {String? stockCurrency}) async =>
      null;
  @override
  Future<Map<String, PriceQuote>> fetchQuotes(
          Map<String, String> symbolByStockId,
          {Map<String, String> currencyByStockId = const {}}) async =>
      {};
  @override
  Future<Decimal?> fetchHistoricalPrice(String symbol, DateTime date,
          {String? stockCurrency}) async =>
      null;
  @override
  Future<List<FetchedDividend>> fetchDividends(String symbol) async => [];
  @override
  Future<AnalystData?> fetchAnalystData(String symbol) async => null;
}

void main() {
  testWidgets('App renders dashboard', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final notificationService = NotificationService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          notificationServiceProvider.overrideWithValue(notificationService),
          marketDataServiceProvider.overrideWithValue(_NoOpMarketDataService()),
          logServiceProvider.overrideWithValue(LogService.forTesting()),
          // Prevents the 4-second startup timer in NextcloudSyncNotifier
          // from leaking into the FakeAsync zone ("Timer still pending").
          nextcloudSyncProvider.overrideWith(_NoOpSyncNotifier.new),
          // Prevents Drift StreamQueryStore cleanup timers from leaking.
          portfolioSummaryProvider.overrideWith(
            (ref) async => PortfolioSummary(
              totalValue: Decimal.zero,
              totalInvested: Decimal.zero,
              unrealisedPnl: Decimal.zero,
              unrealisedPnlPct: Decimal.zero,
              realisedPnl: Decimal.zero,
              allTimeDividends: Decimal.zero,
              currentYearDividends: Decimal.zero,
              currency: 'EUR',
              stockItems: const [],
            ),
          ),
        ],
        child: const StockManagerApp(),
      ),
    );

    await tester.pump();
    expect(find.text('Dashboard'), findsAtLeastNWidgets(1));
    await tester.runAsync(db.close);
  });
}
