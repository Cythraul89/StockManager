import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/services/currency_service.dart';
import 'core/services/isin_lookup_service.dart';
import 'core/services/market_data_service.dart';
import 'core/services/notification_service.dart';
import 'features/settings/settings_provider.dart';
import 'features/stocks/add_stock_screen.dart';
import 'features/stocks/stocks_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase only needed on Android for FCM push notifications.
  // Requires google-services.json in android/app/ — see README.
  if (Platform.isAndroid) {
    // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

  final database = AppDatabase();

  final notificationService = NotificationService();
  await notificationService.initialize();

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
      ],
      child: const StockManagerApp(),
    ),
  );
}
