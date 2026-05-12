import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_manager/app.dart';
import 'package:stock_manager/core/database/app_database.dart';
import 'package:stock_manager/core/services/notification_service.dart';
import 'package:stock_manager/features/dashboard/dashboard_provider.dart';
import 'package:stock_manager/features/settings/settings_provider.dart';
import 'package:stock_manager/features/stocks/stocks_provider.dart';

void main() {
  testWidgets('App renders dashboard', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final notificationService = NotificationService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          notificationServiceProvider.overrideWithValue(notificationService),
          marketDataServiceProvider.overrideWith(
            (ref) => throw UnimplementedError(),
          ),
          // Override portfolioSummaryProvider so no Drift stream providers
          // are subscribed to. Without this, Drift's StreamQueryStore creates
          // zero-duration cleanup timers on cancellation that the test
          // framework detects as pending, causing the test to fail.
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
