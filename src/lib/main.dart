import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/services/background_check_service.dart';
import 'core/services/currency_service.dart';
import 'core/services/isin_lookup_service.dart';
import 'core/services/log_service.dart';
import 'core/services/market_data_service.dart';
import 'core/services/notification_service.dart';
import 'features/settings/settings_provider.dart';
import 'features/stocks/stocks_provider.dart';

// Top-level entry point for WorkManager background tasks (Android only).
// Must be annotated so the Dart AOT compiler does not tree-shake it.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    return BackgroundCheckService.run();
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final logService = await LogService.create();

  // Route all debugPrint calls to both the console and the log file.
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    originalDebugPrint(message, wrapWidth: wrapWidth);
    logService.log(message);
  };

  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['StockManager'],
      'StockManager — personal stock portfolio tracker\n'
      'Copyright (C) 2025 StockManager contributors\n\n'
      'This program is free software: you can redistribute it and/or modify '
      'it under the terms of the GNU General Public License as published by '
      'the Free Software Foundation, either version 3 of the License, or '
      '(at your option) any later version.\n\n'
      'This program is distributed in the hope that it will be useful, '
      'but WITHOUT ANY WARRANTY; without even the implied warranty of '
      'MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the '
      'GNU General Public License for more details.\n\n'
      'You should have received a copy of the GNU General Public License '
      'along with this program. If not, see https://www.gnu.org/licenses/.',
    );
  });

  // Register WorkManager background task for price/rating/dividend checks.
  // ExistingWorkPolicy.keep avoids re-registering on every app launch.
  if (Platform.isAndroid) {
    try {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().registerPeriodicTask(
        'stockBackgroundCheck',
        'checkPricesAndAlerts',
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      // Non-fatal: background price/alert checks will be disabled.
      debugPrint('WorkManager init failed (background checks disabled): $e');
    }
  }

  final database = AppDatabase();

  final notificationService = NotificationService();
  try {
    await notificationService.initialize();
  } catch (e) {
    // Non-fatal: notifications will be silently skipped.
    debugPrint('NotificationService init failed (notifications disabled): $e');
  }

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  final marketDataService = MarketDataService(dio);
  final currencyService = CurrencyService(dio);
  final isinLookupService = IsinLookupService(dio);

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        notificationServiceProvider.overrideWithValue(notificationService),
        marketDataServiceProvider.overrideWithValue(marketDataService),
        currencyServiceProvider.overrideWithValue(currencyService),
        isinLookupServiceProvider.overrideWithValue(isinLookupService),
        logServiceProvider.overrideWithValue(logService),
      ],
      child: const StockManagerApp(),
    ),
  );
}
