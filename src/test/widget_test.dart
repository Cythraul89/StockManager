import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_manager/app.dart';
import 'package:stock_manager/core/database/app_database.dart';
import 'package:stock_manager/core/services/market_data_service.dart';
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

    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsAtLeastNWidget(1));
  });
}
