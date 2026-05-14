import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_settings.dart';
import '../../core/services/nextcloud_service.dart';
import '../stocks/stocks_provider.dart';
import 'settings_provider.dart';

export '../../core/services/nextcloud_service.dart' show RemoteBackupInfo;

enum SyncStatus { idle, syncing, error }

class NextcloudSyncState {
  const NextcloudSyncState({
    this.status = SyncStatus.idle,
    this.lastSyncAt,
    this.error,
    this.pendingRestore,
  });

  final SyncStatus status;
  final DateTime? lastSyncAt;
  final String? error;
  final RemoteBackupInfo? pendingRestore;

  NextcloudSyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncAt,
    String? error,
    RemoteBackupInfo? pendingRestore,
    bool clearPendingRestore = false,
  }) =>
      NextcloudSyncState(
        status: status ?? this.status,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        error: error ?? this.error,
        pendingRestore:
            clearPendingRestore ? null : (pendingRestore ?? this.pendingRestore),
      );
}

final nextcloudSyncProvider =
    NotifierProvider<NextcloudSyncNotifier, NextcloudSyncState>(
        NextcloudSyncNotifier.new);

class NextcloudSyncNotifier extends Notifier<NextcloudSyncState> {
  Timer? _debounce;
  Timer? _startupTimer;

  @override
  NextcloudSyncState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _startupTimer?.cancel();
    });

    _listenToDataChanges();

    // On startup: check for newer remote backup; upload if none found.
    // Stored as a Timer so it can be cancelled on dispose (avoids leaking
    // into test FakeAsync zones and prevents use-after-dispose reads).
    _startupTimer = Timer(const Duration(seconds: 4), _checkAndSync);

    return const NextcloudSyncState();
  }

  void _listenToDataChanges() {
    ref.listen(dataVersionProvider, (_, __) => _scheduleSync());
  }

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), syncNow);
  }

  static const _passwordKey = 'nextcloud_password';

  Future<({String url, String username, String password})?> _credentials() async {
    final settings = await ref.read(settingsProvider.future);
    final url = settings.nextcloudUrl;
    final username = settings.nextcloudUsername;
    if (url == null || url.isEmpty || username == null || username.isEmpty) {
      return null;
    }
    final password =
        await ref.read(secureStorageProvider).read(key: _passwordKey);
    if (password == null || password.isEmpty) return null;
    return (url: url, username: username, password: password);
  }

  // Compare two sync timestamps as local calendar dates to avoid DST issues.
  bool _remoteIsNewer(DateTime? lastSyncAt, DateTime remoteBackupDate) {
    if (lastSyncAt == null) return true;
    final local = lastSyncAt.toLocal();
    final lastSyncDay = DateTime(local.year, local.month, local.day);
    return remoteBackupDate.isAfter(lastSyncDay);
  }

  // On startup: offer restore if remote has a newer backup, else upload.
  Future<void> _checkAndSync() async {
    final creds = await _credentials();
    if (creds == null) return;

    final settings = await ref.read(settingsProvider.future);

    try {
      final remote =
          await ref.read(nextcloudServiceProvider).findLatestBackup(
                serverUrl: creds.url,
                username: creds.username,
                password: creds.password,
                remotePath: settings.nextcloudPath,
              );

      if (remote != null && _remoteIsNewer(settings.lastSyncAt, remote.backupDate)) {
        state = state.copyWith(pendingRestore: remote);
        return;
      }
    } catch (e) {
      // PROPFIND failed (network error, wrong path, etc.) — proceed to upload
      // so a backup is always created on startup.
      debugPrint('NextcloudSync: startup check failed: $e');
    }

    await syncNow();
  }

  // Check whether the server has a newer backup (call after saving credentials).
  Future<void> checkForRemoteBackup() async {
    final creds = await _credentials();
    if (creds == null) return;

    final settings = await ref.read(settingsProvider.future);

    try {
      final remote =
          await ref.read(nextcloudServiceProvider).findLatestBackup(
                serverUrl: creds.url,
                username: creds.username,
                password: creds.password,
                remotePath: settings.nextcloudPath,
              );

      if (remote != null && _remoteIsNewer(settings.lastSyncAt, remote.backupDate)) {
        state = state.copyWith(pendingRestore: remote);
      }
    } catch (_) {}
  }

  // Download and import the pending remote backup.
  Future<void> restoreFromRemote() async {
    final info = state.pendingRestore;
    if (info == null) return;

    final creds = await _credentials();
    if (creds == null) return;

    state = state.copyWith(status: SyncStatus.syncing, error: null);

    try {
      final bytes = await ref.read(nextcloudServiceProvider).downloadFile(
            serverUrl: creds.url,
            username: creds.username,
            password: creds.password,
            remotePath: info.remotePath,
          );

      await ref.read(backupServiceProvider).importFromBytes(bytes);

      final now = DateTime.now();
      final settings = await ref.read(settingsProvider.future);
      await ref
          .read(settingsActionsProvider)
          .saveSettings(settings.copyWith(lastSyncAt: now));

      state = NextcloudSyncState(status: SyncStatus.idle, lastSyncAt: now);
    } catch (e) {
      state =
          state.copyWith(status: SyncStatus.error, error: 'Restore failed: $e');
    }
  }

  void dismissRestore() {
    state = state.copyWith(clearPendingRestore: true);
  }

  Future<void> syncNow() async {
    _debounce?.cancel();

    // Don't auto-upload while a remote restore is pending user decision.
    if (state.pendingRestore != null) return;

    final creds = await _credentials();
    if (creds == null) return;

    state = state.copyWith(status: SyncStatus.syncing, error: null);

    try {
      final settings = await ref.read(settingsProvider.future);
      final backupFile = await ref.read(backupServiceProvider).exportToZip();
      final bytes = await backupFile.readAsBytes();

      final dir = settings.nextcloudPath;
      final dateStr =
          DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final remotePath =
          '${dir.endsWith('/') ? dir : '$dir/'}stockmanager_backup_$dateStr.zip';

      await ref.read(nextcloudServiceProvider).uploadBackup(
            serverUrl: creds.url,
            username: creds.username,
            password: creds.password,
            remotePath: remotePath,
            bytes: bytes,
          );

      final now = DateTime.now();
      await ref.read(settingsActionsProvider).saveSettings(
            settings.copyWith(lastSyncAt: now),
          );

      state = NextcloudSyncState(status: SyncStatus.idle, lastSyncAt: now);

      // Prune old backups according to the keep-exports setting.
      await _pruneOldBackups(creds: creds, settings: settings);
    } catch (e) {
      state = state.copyWith(status: SyncStatus.error, error: e.toString());
    }
  }

  Future<void> _pruneOldBackups({
    required ({String url, String username, String password}) creds,
    required AppSettings settings,
  }) async {
    final service = ref.read(nextcloudServiceProvider);

    List<String> hrefs;
    try {
      hrefs = await service.listFiles(
        serverUrl: creds.url,
        username: creds.username,
        password: creds.password,
        remotePath: settings.nextcloudPath,
      );
    } catch (_) {
      return; // Best effort — don't fail sync if listing fails
    }

    final pattern = RegExp(r'stockmanager_backup_(\d{4}-\d{2}-\d{2})\.zip$');
    final backups = <(DateTime, String)>[];
    for (final href in hrefs) {
      final decoded = Uri.decodeFull(href);
      final match = pattern.firstMatch(decoded);
      if (match == null) continue;
      final date = DateTime.tryParse(match.group(1)!);
      if (date != null) backups.add((date, href));
    }

    backups.sort((a, b) => b.$1.compareTo(a.$1)); // newest first

    final keep = settings.nextcloudKeepExports;
    for (final backup in backups.skip(keep)) {
      try {
        await service.delete(
          serverUrl: creds.url,
          username: creds.username,
          password: creds.password,
          remotePath: backup.$2,
        );
      } catch (_) {
        // Best effort — continue pruning remaining backups
      }
    }
  }
}
