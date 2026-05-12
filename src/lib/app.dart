import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/models/app_settings.dart';
import 'features/brokers/add_broker_screen.dart';
import 'features/brokers/brokers_screen.dart';
import 'features/brokers/edit_broker_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/dividends/add_dividend_screen.dart';
import 'features/dividends/dividends_screen.dart';
import 'features/settings/currency_settings_screen.dart';
import 'features/settings/nextcloud_settings_screen.dart';
import 'features/settings/notification_settings_screen.dart';
import 'features/settings/settings_provider.dart';
import 'features/settings/settings_screen.dart';
import 'features/stocks/add_stock_screen.dart';
import 'features/stocks/edit_stock_screen.dart';
import 'features/stocks/stock_detail_screen.dart';
import 'features/stocks/stocks_screen.dart';
import 'features/transactions/add_transaction_screen.dart';
import 'shell/adaptive_shell.dart';

class StockManagerApp extends ConsumerWidget {
  const StockManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsStreamProvider);
    final themeMode = settingsAsync.whenOrNull(
          data: (s) => switch (s.theme) {
            AppTheme.light => ThemeMode.light,
            AppTheme.dark => ThemeMode.dark,
            AppTheme.system => ThemeMode.system,
          },
        ) ??
        ThemeMode.system;

    return MaterialApp.router(
      title: 'StockManager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AdaptiveShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/stocks',
          builder: (context, state) => const StocksScreen(),
          routes: [
            GoRoute(
              path: 'add',
              builder: (context, state) => const AddStockScreen(),
            ),
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  StockDetailScreen(id: state.pathParameters['id']!),
              routes: [
                GoRoute(
                  path: 'edit',
                  builder: (context, state) =>
                      EditStockScreen(id: state.pathParameters['id']!),
                ),
                GoRoute(
                  path: 'transactions/add',
                  builder: (context, state) => AddTransactionScreen(
                      stockId: state.pathParameters['id']!),
                ),
                GoRoute(
                  path: 'dividends/add',
                  builder: (context, state) => AddDividendScreen(
                      stockId: state.pathParameters['id']!),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/dividends',
          builder: (context, state) => const DividendsScreen(),
        ),
        GoRoute(
          path: '/brokers',
          builder: (context, state) => const BrokersScreen(),
          routes: [
            GoRoute(
              path: 'add',
              builder: (context, state) => const AddBrokerScreen(),
            ),
            GoRoute(
              path: ':id/edit',
              builder: (context, state) =>
                  EditBrokerScreen(id: state.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
          routes: [
            GoRoute(
              path: 'nextcloud',
              builder: (context, state) => const NextcloudSettingsScreen(),
            ),
            GoRoute(
              path: 'currency',
              builder: (context, state) => const CurrencySettingsScreen(),
            ),
            GoRoute(
              path: 'notifications',
              builder: (context, state) =>
                  const NotificationSettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
