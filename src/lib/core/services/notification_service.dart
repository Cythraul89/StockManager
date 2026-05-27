import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open',
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    await _plugin.initialize(settings);
    // POST_NOTIFICATIONS runtime permission is requested separately via
    // requestAndroidPermission(), called after the first frame in main.dart.
    // Requesting it here (before runApp) can cause a JVM SecurityException on
    // Android 13+ if the permission is not yet declared in the merged manifest.
  }

  /// Requests the POST_NOTIFICATIONS runtime permission on Android 13+.
  ///
  /// Call this after the app's first frame is rendered (Activity in RESUMED
  /// state). Safe to call on older Android versions — returns null silently.
  Future<bool?> requestAndroidPermission() async {
    if (!Platform.isAndroid) return null;
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return androidPlugin?.requestNotificationsPermission();
  }

  Future<void> showPriceAlert({
    required String stockName,
    required String symbol,
    required double changePct,
  }) async {
    final direction = changePct >= 0 ? '▲' : '▼';
    final pct = changePct.abs().toStringAsFixed(2);
    await _show(
      id: symbol.hashCode & 0x7fffffff,
      title: '$stockName price alert',
      body: '$symbol $direction$pct% — tap to view',
      channelId: 'price_alerts',
      channelName: 'Price alerts',
    );
  }

  Future<void> showDividendAlert({
    required String stockName,
    required String symbol,
    required int daysUntil,
  }) async {
    final when = daysUntil == 0
        ? 'today'
        : daysUntil == 1
            ? 'tomorrow'
            : 'in $daysUntil days';
    await _show(
      id: ('div_$symbol').hashCode & 0x7fffffff,
      title: 'Dividend coming up',
      body: '$stockName ($symbol) dividend is expected $when',
      channelId: 'dividend_alerts',
      channelName: 'Dividend alerts',
    );
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.high,
      priority: Priority.high,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
      linux: const LinuxNotificationDetails(),
    );
    await _plugin.show(id, title, body, details);
  }

  Future<void> showRatingChangeAlert({
    required String stockName,
    required String symbol,
    required String oldRating,
    required String newRating,
  }) async {
    await _show(
      id: ('rating_$symbol').hashCode & 0x7fffffff,
      title: 'Analyst rating changed: $stockName',
      body: '$symbol: $oldRating → $newRating',
      channelId: 'rating_alerts',
      channelName: 'Analyst rating alerts',
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();
}
