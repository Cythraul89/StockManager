import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  }) =>
      NextcloudSyncState(
        status: status ?? this.status,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        error: error ?? this.error,
        pendingRestore: pendingRestore ?? this.pendingRestore,
      );
}

final nextcloudSyncProvider =
    NotifierProvider<NextcloudSyncNotifier, NextcloudSyncState>(
        NextcloudSyncNotifier.new);

class NextcloudSyncNotifier extends Notifier<NextcloudSyncState> {
  Timer? _debounce;

  @override
  NextcloudSyncState build() {
    ref.onDispose(() => _debounce?.cancel());

    _listenToDataChanges();

    // On startup: check for newer remote backup; upload if none found.
    Future.delayed(const Duration(seconds: 4), _checkAndSync);

    return const NextcloudSyncState();
  }

  void _listenToDataChanges() {
    ref.listen(dataVersionProvider, (_, __) => scheduleSync());
  }

  void scheduleSync() {
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

      if (remote != null) {
        final lastSync = settings.lastSyncAt;
        final remoteIsNewer = lastSync == null ||
            remote.backupDate.isAfter(
                DateTime.utc(lastSync.year, lastSync.month, lastSync.day));
        if (remoteIsNewer) {
          state = state.copyWith(pendingRestore: remote);
          return;
        }
      }
    } catch (_) {
      // Silently ignore — proceed to upload.
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

      if (remote != null) {
        final lastSync = settings.lastSyncAt;
        final remoteIsNewer = lastSync == null ||
            remote.backupDate.isAfter(
                DateTime.utc(lastSync.year, lastSync.month, lastSync.day));
        if (remoteIsNewer) {
          state = state.copyWith(pendingRestore: remote);
        }
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
    state = NextcloudSyncState(
      status: state.status,
      lastSyncAt: state.lastSyncAt,
      error: state.error,
    );
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
    } catch (e) {
      state = state.copyWith(status: SyncStatus.error, error: e.toString());
    }
  }
}
