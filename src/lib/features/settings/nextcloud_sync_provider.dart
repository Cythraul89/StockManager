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

  // Always reads directly from the database so the result is never stale.
  // FutureProvider caches its value until invalidated, which means reading
  // settingsProvider immediately after saveSettings() returns old data.
  Future<({String url, String username, String password, String path, String? fingerprint})?> _credentials() async {
    final row =
        await ref.read(databaseProvider).settingsDao.getSettings();
    final url = row?.nextcloudUrl;
    final username = row?.nextcloudUsername;
    if (url == null || url.isEmpty || username == null || username.isEmpty) {
      return null;
    }
    final password = row?.nextcloudPassword;
    if (password == null || password.isEmpty) return null;
    return (
      url: url,
      username: username,
      password: password,
      path: row!.nextcloudPath,
      fingerprint: row.nextcloudCertFingerprint,
    );
  }

  // Parses both the legacy date-only format (YYYY-MM-DD → midnight UTC) and
  // the current datetime format (YYYY-MM-DDTHH-MM-SSZ → full UTC instant).
  static DateTime? _parseBackupTimestamp(String s) {
    if (s.contains('T')) {
      final normalized = s.replaceAllMapped(
        RegExp(r'T(\d{2})-(\d{2})-(\d{2})Z'),
        (m) => 'T${m[1]}:${m[2]}:${m[3]}Z',
      );
      return DateTime.tryParse(normalized);
    }
    return DateTime.tryParse(s);
  }

  // Returns true when the remote backup was created after the last local sync.
  bool _remoteIsNewer(DateTime? lastSyncAt, DateTime remoteBackupDate) {
    if (lastSyncAt == null) return true;
    return remoteBackupDate.isAfter(lastSyncAt);
  }

  // On startup: offer restore if remote has a newer backup, else upload.
  Future<void> _checkAndSync() async {
    final creds = await _credentials();
    if (creds == null) return;

    try {
      final remote =
          await ref.read(nextcloudServiceProvider).findLatestBackup(
                serverUrl: creds.url,
                username: creds.username,
                password: creds.password,
                remotePath: creds.path,
                pinnedFingerprint: creds.fingerprint,
              );

      // lastSyncAt is only needed for comparison here; reading settingsProvider
      // is acceptable since this runs on startup when the cache is still fresh.
      final settings = await ref.read(settingsProvider.future);
      if (remote != null &&
          _remoteIsNewer(settings.lastSyncAt, remote.backupDate)) {
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

    try {
      final remote =
          await ref.read(nextcloudServiceProvider).findLatestBackup(
                serverUrl: creds.url,
                username: creds.username,
                password: creds.password,
                remotePath: creds.path,
                pinnedFingerprint: creds.fingerprint,
              );

      // Read lastSyncAt directly from the DAO so a stale settingsProvider
      // cache (common when called immediately after saveSettings()) does not
      // cause _remoteIsNewer to compare against an outdated timestamp.
      final row = await ref.read(databaseProvider).settingsDao.getSettings();
      if (remote != null &&
          _remoteIsNewer(row?.lastSyncAt, remote.backupDate)) {
        state = state.copyWith(pendingRestore: remote);
      }
    } catch (e) {
      debugPrint('NextcloudSync: checkForRemoteBackup failed: $e');
    }
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
            pinnedFingerprint: creds.fingerprint,
          );

      final skipped =
          await ref.read(backupServiceProvider).importFromBytes(bytes);

      final now = DateTime.now();
      await ref.read(settingsActionsProvider).saveLastSyncAt(now);

      state = NextcloudSyncState(
        status: SyncStatus.idle,
        lastSyncAt: now,
        error: skipped > 0
            ? '$skipped row(s) were skipped during restore due to missing '
                'stock references in the backup.'
            : null,
      );
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
      final backupFile = await ref.read(backupServiceProvider).exportToZip();
      final bytes = await backupFile.readAsBytes();

      final utcNow = DateTime.now().toUtc();
      // Use full UTC timestamp so cross-device _remoteIsNewer comparisons work
      // within the same day. Colons replaced with hyphens for filename safety.
      final dateTimeStr = '${utcNow.toIso8601String().substring(0, 19).replaceAll(':', '-')}Z';
      final dir = creds.path;
      final remotePath =
          '${dir.endsWith('/') ? dir : '$dir/'}stockmanager_backup_$dateTimeStr.zip';

      await ref.read(nextcloudServiceProvider).uploadBackup(
            serverUrl: creds.url,
            username: creds.username,
            password: creds.password,
            remotePath: remotePath,
            bytes: bytes,
            pinnedFingerprint: creds.fingerprint,
          );

      final now = DateTime.now();
      await ref.read(settingsActionsProvider).saveLastSyncAt(now);

      state = NextcloudSyncState(status: SyncStatus.idle, lastSyncAt: now);

      // Prune old backups according to the keep-exports setting.
      await _pruneOldBackups(creds: creds);
    } catch (e) {
      final msg = e.toString();
      final friendly = msg.contains('CERTIFICATE_VERIFY_FAILED') ||
              msg.contains('HandshakeException')
          ? 'Certificate not trusted. Open Nextcloud Sync settings and press "Test connection" to re-accept the certificate.'
          : msg;
      state = state.copyWith(status: SyncStatus.error, error: friendly);
    }
  }

  Future<void> _pruneOldBackups({
    required ({String url, String username, String password, String path, String? fingerprint}) creds,
  }) async {
    final service = ref.read(nextcloudServiceProvider);

    List<String> hrefs;
    try {
      hrefs = await service.listFiles(
        serverUrl: creds.url,
        username: creds.username,
        password: creds.password,
        remotePath: creds.path,
        pinnedFingerprint: creds.fingerprint,
      );
    } catch (_) {
      return; // Best effort — don't fail sync if listing fails
    }

    // Read keep-exports setting directly from DB to avoid stale provider data.
    final row = await ref.read(databaseProvider).settingsDao.getSettings();
    final keep = row?.nextcloudKeepExports ?? AppSettings.defaults.nextcloudKeepExports;

    final pattern = RegExp(r'stockmanager_backup_(\d{4}-\d{2}-\d{2}(?:T\d{2}-\d{2}-\d{2}Z)?)\.zip$');
    final backups = <(DateTime, String)>[];
    for (final href in hrefs) {
      final decoded = Uri.decodeFull(href);
      final match = pattern.firstMatch(decoded);
      if (match == null) continue;
      final date = _parseBackupTimestamp(match.group(1)!);
      if (date != null) backups.add((date, href));
    }

    backups.sort((a, b) => b.$1.compareTo(a.$1)); // newest first

    for (final backup in backups.skip(keep)) {
      try {
        await service.delete(
          serverUrl: creds.url,
          username: creds.username,
          password: creds.password,
          remotePath: backup.$2,
          pinnedFingerprint: creds.fingerprint,
        );
      } catch (_) {
        // Best effort — continue pruning remaining backups
      }
    }
  }
}
