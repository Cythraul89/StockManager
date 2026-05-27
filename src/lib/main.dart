import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
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

// ─── Crash-log helpers ────────────────────────────────────────────────────
//
// A lightweight diagnostic file written step-by-step through startup.
// On a successful first frame it is deleted. If the process dies before
// that, the next launch finds the file and shows it on-screen so the user
// can screenshot the last recorded step without needing ADB/logcat.

Future<File?> _crashLogFile() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/stockmanager_crash.txt');
  } catch (_) {
    return null;
  }
}

Future<String?> _readPreviousCrashLog() async {
  try {
    final f = await _crashLogFile();
    if (f == null || !await f.exists()) return null;
    final s = await f.readAsString();
    return s.trim().isEmpty ? null : s;
  } catch (_) {
    return null;
  }
}

Future<void> _appendCrashLog(String msg) async {
  try {
    final f = await _crashLogFile();
    await f?.writeAsString('$msg\n', mode: FileMode.append);
  } catch (_) {}
}

Future<void> _clearCrashLog() async {
  try {
    final f = await _crashLogFile();
    await f?.delete();
  } catch (_) {}
}

// ─── Crash-report screen ─────────────────────────────────────────────────

class _CrashReportApp extends StatelessWidget {
  const _CrashReportApp({super.key, required this.log, required this.onProceed});
  final String log;
  final VoidCallback onProceed;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFFFF3E0),
        appBar: AppBar(
          title: const Text('Startup diagnostic'),
          backgroundColor: Colors.deepOrange,
          foregroundColor: Colors.white,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'The previous session ended unexpectedly.\n'
                'Screenshot this and report it, then tap the button below.',
                style: TextStyle(
                  color: Colors.deepOrange[900],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.all(8),
                color: Colors.black,
                child: SingleChildScrollView(
                  child: SelectableText(
                    log,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: onProceed,
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepOrange),
                child: const Text('Clear and launch app'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Entry points ─────────────────────────────────────────────────────────

void main() {
  runZonedGuarded(_mainWithDiag, (error, stack) {
    _appendCrashLog('CRASH: $error\n$stack');
    debugPrint('Uncaught error: $error\n$stack');
  });
}

Future<void> _mainWithDiag() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Show crash report from a previous failed session (if any) before
  // attempting a new startup — so the user can screenshot the log without
  // needing ADB or a file manager.
  final prevLog = await _readPreviousCrashLog();
  if (prevLog != null) {
    final proceed = Completer<void>();
    runApp(_CrashReportApp(log: prevLog, onProceed: () => proceed.complete()));
    await proceed.future;
    await _clearCrashLog();
  }

  await _main();
}

Future<void> _main() async {
  await _appendCrashLog(
      '=== ${DateTime.now().toIso8601String()} ===');
  await _appendCrashLog('[1] WidgetsFlutterBinding initialized');

  final logService = await LogService.create();
  await _appendCrashLog('[2] LogService created');

  // Route all debugPrint calls to both the console and the log file.
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    originalDebugPrint(message, wrapWidth: wrapWidth);
    logService.log(message);
  };
  await _appendCrashLog('[3] debugPrint override set');

  // Save the original handler (Flutter's default, which logs to console in
  // debug mode and is silent in release). Call it first so release-mode
  // error reporting is not suppressed, then also write to our log file.
  // Do NOT call FlutterError.presentError() here — it internally calls
  // onError?.call(details), which would recurse back into this handler.
  final origOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    origOnError?.call(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
  };
  await _appendCrashLog('[4] FlutterError.onError set');

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
  await _appendCrashLog('[5] LicenseRegistry configured');

  // Register WorkManager background task for price/rating/dividend checks.
  // ExistingWorkPolicy.keep avoids re-registering on every app launch.
  if (Platform.isAndroid) {
    try {
      await _appendCrashLog('[6a] WorkManager.initialize starting');
      await Workmanager().initialize(callbackDispatcher);
      await _appendCrashLog('[6b] WorkManager.initialize OK');
      await Workmanager().registerPeriodicTask(
        'stockBackgroundCheck',
        'checkPricesAndAlerts',
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
      await _appendCrashLog('[6c] WorkManager.registerPeriodicTask OK');
    } catch (e) {
      // Non-fatal: background price/alert checks will be disabled.
      debugPrint('WorkManager init failed (background checks disabled): $e');
      await _appendCrashLog('[6!] WorkManager FAILED: $e');
    }
  }

  final database = AppDatabase();
  await _appendCrashLog('[7] AppDatabase() created');

  final notificationService = NotificationService();
  try {
    await _appendCrashLog('[8a] NotificationService.initialize starting');
    await notificationService.initialize();
    await _appendCrashLog('[8b] NotificationService.initialize OK');
  } catch (e) {
    // Non-fatal: notifications will be silently skipped.
    debugPrint('NotificationService init failed (notifications disabled): $e');
    await _appendCrashLog('[8!] NotificationService FAILED: $e');
  }

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  final marketDataService = MarketDataService(dio);
  final currencyService = CurrencyService(dio);
  final isinLookupService = IsinLookupService(dio);
  await _appendCrashLog('[9] Services (Dio/MarketData/Currency/ISIN) created');

  await _appendCrashLog('[10] runApp starting');
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
  await _appendCrashLog('[11] runApp returned');

  // Request POST_NOTIFICATIONS permission after the first frame — the Activity
  // must be in RESUMED state before we call requestPermissions on Android 13+.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _appendCrashLog('[12a] postFrameCallback fired');
    try {
      await notificationService.requestAndroidPermission();
      await _appendCrashLog('[12b] requestAndroidPermission OK');
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
      await _appendCrashLog('[12!] requestAndroidPermission FAILED: $e');
    }
    // Wait for async provider/database work to settle before declaring the
    // session clean. Crashes in Riverpod providers (SQLite open, network init)
    // happen asynchronously after the first frame; clearing too early means
    // the diagnostic log is gone before it records the failure.
    await Future.delayed(const Duration(seconds: 15));
    await _clearCrashLog();
  });
}
