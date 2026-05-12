import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_manager/app.dart';
import 'package:stock_manager/core/database/app_database.dart';
import 'package:stock_manager/core/services/notification_service.dart';
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
        ],
        child: const StockManagerApp(),
      ),
    );

    // One pump renders the first frame; the Dashboard AppBar title is
    // visible immediately regardless of provider loading state.
    await tester.pump();
    expect(find.text('Dashboard'), findsAtLeastNWidgets(1));

    // Explicitly dispose the widget tree so Riverpod cancels its Drift
    // stream subscriptions now, then pump once to drain the zero-duration
    // cleanup timers Drift creates on cancellation. Without this, those
    // timers are still pending when the test framework runs its invariant
    // check, causing a spurious failure.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    // db.close() uses futures internally; run it outside FakeAsync so those
    // futures resolve without needing additional pump() calls.
    await tester.runAsync(db.close);
  });
}
