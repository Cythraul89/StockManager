import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../stocks/stocks_provider.dart';
import 'settings_provider.dart';

enum SyncStatus { idle, syncing, error }

class NextcloudSyncState {
  const NextcloudSyncState({
    this.status = SyncStatus.idle,
    this.lastSyncAt,
    this.error,
  });

  final SyncStatus status;
  final DateTime? lastSyncAt;
  final String? error;

  NextcloudSyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncAt,
    String? error,
  }) =>
      NextcloudSyncState(
        status: status ?? this.status,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        error: error ?? this.error,
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

    // Watch for any data mutation and schedule a debounced upload.
    _listenToDataChanges();

    // Trigger an upload shortly after startup.
    Future.delayed(const Duration(seconds: 4), syncNow);

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

  Future<void> syncNow() async {
    _debounce?.cancel();

    final settings = await ref.read(settingsProvider.future);
    final url = settings.nextcloudUrl;
    final username = settings.nextcloudUsername;
    if (url == null || url.isEmpty || username == null || username.isEmpty) {
      return;
    }

    final password =
        await ref.read(secureStorageProvider).read(key: _passwordKey);
    if (password == null || password.isEmpty) return;

    state = state.copyWith(status: SyncStatus.syncing, error: null);

    try {
      final backupFile =
          await ref.read(backupServiceProvider).exportToZip();
      final bytes = await backupFile.readAsBytes();

      final dir = settings.nextcloudPath;
      final dateStr =
          DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final remotePath =
          '${dir.endsWith('/') ? dir : '$dir/'}stockmanager_backup_$dateStr.zip';

      await ref.read(nextcloudServiceProvider).uploadBackup(
            serverUrl: url,
            username: username,
            password: password,
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
