import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import 'market_data_service.dart';

// Runs inside a WorkManager background isolate (Android only).
// Opens its own DB connection and HTTP client — no Riverpod providers.
class BackgroundCheckService {
  static const _priceChannelId = 'price_alerts';
  static const _priceChannelName = 'Price alerts';
  static const _ratingChannelId = 'rating_alerts';
  static const _ratingChannelName = 'Analyst rating alerts';
  static const _dividendChannelId = 'dividend_alerts';
  static const _dividendChannelName = 'Dividend alerts';

  static Future<bool> run() async {
    AppDatabase? db;
    try {
      final dbFolder = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(dbFolder.path, 'stock_manager.sqlite'));
      db = AppDatabase.background(dbFile);

      final settings = await db.settingsDao.getSettings();
      if (settings == null || !settings.notificationsEnabled) return true;

      final thresholdPct = settings.priceAlertThresholdPct.toDouble();
      final dividendAlertDays = settings.dividendAlertDays;
      final marketDataProvider = settings.marketDataProvider;
      final finnhubApiKey = settings.finnhubApiKey;

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final marketData = MarketDataService(dio);

      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));

      final stocks = await db.stocksDao.getAll();
      // Rating and dividend checks run at most once per calendar day to avoid
      // hammering the analyst API (100+ requests per 15-min cycle) and to
      // prevent the same dividend notification firing on every cycle.
      final firstRunToday = await _isFirstRunToday(dbFolder.path);

      for (final stock in stocks) {
        try {
          await _checkPrice(db, plugin, marketData, stock, thresholdPct);
        } catch (e) {
          debugPrint('BackgroundCheck: price failed for ${stock.symbol}: $e');
        }

        if (firstRunToday) {
          try {
            await _checkRating(
              db, plugin, marketData, stock, marketDataProvider, finnhubApiKey,
            );
          } catch (e) {
            debugPrint('BackgroundCheck: rating failed for ${stock.symbol}: $e');
          }
        }
      }

      if (firstRunToday) {
        try {
          await _checkDividends(db, plugin, stocks, dividendAlertDays);
        } catch (e) {
          debugPrint('BackgroundCheck: dividend check failed: $e');
        }
      }

      return true;
    } catch (e) {
      debugPrint('BackgroundCheckService.run failed: $e');
      return false;
    } finally {
      await db?.close();
    }
  }

  static Future<bool> _isFirstRunToday(String dirPath) async {
    try {
      final file = File(p.join(dirPath, 'background_check_last_run.txt'));
      final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      if (await file.exists()) {
        final last = await file.readAsString();
        if (last.trim() == today) return false;
      }
      await file.writeAsString(today);
      return true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> _checkPrice(
    AppDatabase db,
    FlutterLocalNotificationsPlugin plugin,
    MarketDataService marketData,
    StockRow stock,
    double thresholdPct,
  ) async {
    final quote = await marketData.fetchQuote(
      stock.symbol,
      stock.id,
      stockCurrency: stock.currency,
    );
    if (quote == null) return;

    final cached = await db.stocksDao.getCachedPrice(stock.id);
    if (cached != null && !cached.manualOverride) {
      final oldPrice = cached.price.toDouble();
      final newPrice = quote.price.toDouble();
      if (oldPrice > 0) {
        final changePct = ((newPrice - oldPrice) / oldPrice) * 100;
        if (changePct.abs() >= thresholdPct) {
          final direction = changePct >= 0 ? '▲' : '▼';
          final pct = changePct.abs().toStringAsFixed(2);
          await _show(
            plugin,
            id: stock.symbol.hashCode & 0x7fffffff,
            title: '${stock.name} price alert',
            body: '${stock.symbol} $direction$pct%',
            channelId: _priceChannelId,
            channelName: _priceChannelName,
          );
        }
      }
    }

    await db.stocksDao.upsertPrice(PriceCacheCompanion.insert(
      stockId: stock.id,
      price: quote.price,
      currency: quote.currency,
      fetchedAt: quote.fetchedAt,
      manualOverride: const Value(false),
    ));
  }

  static Future<void> _checkRating(
    AppDatabase db,
    FlutterLocalNotificationsPlugin plugin,
    MarketDataService marketData,
    StockRow stock,
    String marketDataProvider,
    String? finnhubApiKey,
  ) async {
    final analystData = marketDataProvider == 'finnhub' &&
            finnhubApiKey != null &&
            finnhubApiKey.isNotEmpty
        ? await marketData.fetchAnalystDataFinnhubWithFallback(
            stock.symbol, finnhubApiKey)
        : await marketData.fetchAnalystData(stock.symbol);

    final newConsensus = analystData?.recommendationKey;
    final oldConsensus = stock.lastKnownConsensus;

    if (newConsensus != null &&
        oldConsensus != null &&
        newConsensus != oldConsensus) {
      await _show(
        plugin,
        id: ('rating_${stock.symbol}').hashCode & 0x7fffffff,
        title: 'Analyst rating changed: ${stock.name}',
        body:
            '${stock.symbol}: ${_formatRating(oldConsensus)} → ${_formatRating(newConsensus)}',
        channelId: _ratingChannelId,
        channelName: _ratingChannelName,
      );
    }

    if (newConsensus != oldConsensus) {
      await db.stocksDao.updateLastKnownConsensus(stock.id, newConsensus);
    }
  }

  static Future<void> _checkDividends(
    AppDatabase db,
    FlutterLocalNotificationsPlugin plugin,
    List<StockRow> stocks,
    int dividendAlertDays,
  ) async {
    final stockMap = {for (final s in stocks) s.id: s};
    final today = DateTime.now();
    final cutoff = today.add(Duration(days: dividendAlertDays));
    final expected = await db.dividendsDao.getExpected();

    for (final div in expected) {
      if (!div.date.isAfter(today) || div.date.isAfter(cutoff)) continue;
      final stock = stockMap[div.stockId];
      if (stock == null) continue;
      final daysUntil = div.date.difference(today).inDays;
      final when = daysUntil == 0
          ? 'today'
          : daysUntil == 1
              ? 'tomorrow'
              : 'in $daysUntil days';
      await _show(
        plugin,
        id: ('div_${stock.symbol}').hashCode & 0x7fffffff,
        title: 'Dividend coming up',
        body: '${stock.name} (${stock.symbol}) dividend expected $when',
        channelId: _dividendChannelId,
        channelName: _dividendChannelName,
      );
    }
  }

  static Future<void> _show(
    FlutterLocalNotificationsPlugin plugin, {
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
  }) =>
      plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );

  static String _formatRating(String key) => switch (key.toLowerCase()) {
        'strongbuy' || 'strong_buy' => 'Strong Buy',
        'buy' => 'Buy',
        'hold' => 'Hold',
        'underperform' => 'Underperform',
        'sell' => 'Sell',
        'strongsell' || 'strong_sell' => 'Strong Sell',
        _ => key,
      };
}
