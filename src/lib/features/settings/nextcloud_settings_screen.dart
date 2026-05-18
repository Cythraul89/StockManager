import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/nextcloud_service.dart';
import 'nextcloud_sync_provider.dart';
import 'settings_provider.dart';

enum _SyncChoice { restore, upload }

class NextcloudSettingsScreen extends ConsumerStatefulWidget {
  const NextcloudSettingsScreen({super.key});

  @override
  ConsumerState<NextcloudSettingsScreen> createState() =>
      _NextcloudSettingsScreenState();
}

class _NextcloudSettingsScreenState
    extends ConsumerState<NextcloudSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();

  bool _loaded = false;
  bool _isTesting = false;
  bool _isSaving = false;
  bool _obscurePassword = true;
  String? _connectionStatus;
  bool _connectionVerified = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  void _invalidateVerification() {
    if (_connectionVerified) setState(() => _connectionVerified = false);
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _connectionStatus = null;
      _connectionVerified = false;
    });

    final service = ref.read(nextcloudServiceProvider);
    final url = _urlCtrl.text.trim();

    try {
      final certInfo = await service.fetchCertificateInfo(url);
      if (!mounted) return;

      String? fingerprint;
      if (certInfo != null) {
        final approved = await _showCertDialog(certInfo);
        if (approved != true) {
          setState(() => _connectionStatus = 'Certificate not trusted.');
          return;
        }
        fingerprint = certInfo.fingerprint;
        await ref.read(settingsActionsProvider).saveCertFingerprint(fingerprint);
      }

      await service.verifyCredentials(
        serverUrl: url,
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        pinnedFingerprint: fingerprint ??
            (await ref.read(settingsProvider.future)).nextcloudCertFingerprint,
      );

      if (mounted) {
        setState(() {
          _connectionStatus = 'Connection verified.';
          _connectionVerified = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _connectionStatus = 'Connection failed: $e');
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final settings = await ref.read(settingsProvider.future);
      await ref.read(settingsActionsProvider).saveSettings(
            settings.copyWith(
              nextcloudUrl: _urlCtrl.text.trim(),
              nextcloudUsername: _usernameCtrl.text.trim(),
              nextcloudPassword: _passwordCtrl.text,
              nextcloudPath: _pathCtrl.text.trim(),
            ),
          );

      if (!mounted) return;

      // 2. Check for any existing backup on the server.
      final notifier = ref.read(nextcloudSyncProvider.notifier);
      final remoteBackup = await notifier.findRemoteBackup();
      if (!mounted) return;

      // 3. Ask what to do (restore vs. upload; null = user dismissed = skip).
      final choice = await _showSyncChoiceDialog(remoteBackup);
      if (!mounted) return;

      // 4. Execute the chosen action.
      if (choice == _SyncChoice.restore && remoteBackup != null) {
        notifier.setPendingRestore(remoteBackup);
        await notifier.restoreFromRemote();
        if (!mounted) return;
        if (ref.read(nextcloudSyncProvider).status == SyncStatus.error) return;
      } else if (choice == _SyncChoice.upload) {
        await notifier.syncNow();
        if (!mounted) return;
      }

      // 5. Return to settings — invalidate first so re-opening this screen
      //    reads fresh credentials from the DB instead of the stale cache.
      if (mounted) {
        ref.invalidate(settingsProvider);
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool?> _showCertDialog(CertificateInfo info) => showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Untrusted certificate'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'This server uses a certificate that is not trusted by the system.'),
              const SizedBox(height: 12),
              _certRow('Subject', info.subject),
              _certRow('Issuer', info.issuer),
              _certRow('Valid until',
                  info.validUntil.toIso8601String().substring(0, 10)),
              _certRow('SHA-256', info.fingerprint),
              const SizedBox(height: 12),
              const Text(
                  'Only trust this certificate if you have verified the fingerprint '
                  'matches your server.'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Reject')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Trust & pin')),
          ],
        ),
      );

  Future<_SyncChoice?> _showSyncChoiceDialog(RemoteBackupInfo? remote) =>
      showDialog<_SyncChoice>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(remote != null
              ? 'Server backup found'
              : 'Connected to Nextcloud'),
          content: Text(
            remote != null
                ? 'A backup from '
                    '${remote.backupDate.toIso8601String().substring(0, 10)} '
                    'was found on your Nextcloud server.\n\n'
                    'Restore from server, or upload your current data?'
                : 'No existing backup was found on the server.\n\n'
                    'Upload a backup of your current data now?',
          ),
          actions: remote != null
              ? [
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(ctx, _SyncChoice.upload),
                    child: const Text('Upload current data'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(ctx, _SyncChoice.restore),
                    child: const Text('Restore from server'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Later'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(ctx, _SyncChoice.upload),
                    child: const Text('Upload now'),
                  ),
                ],
        ),
      );

  Widget _certRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 80,
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final syncState = ref.watch(nextcloudSyncProvider);
    final busy =
        _isTesting || _isSaving || syncState.status == SyncStatus.syncing;

    return Scaffold(
      appBar: AppBar(title: const Text('Nextcloud Sync')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) {
          if (!_loaded) {
            _urlCtrl.text = settings.nextcloudUrl ?? '';
            _usernameCtrl.text = settings.nextcloudUsername ?? '';
            _pathCtrl.text = settings.nextcloudPath;
            _loaded = true;
            // Treat existing, previously synced credentials as already verified.
            // Use settings.lastSyncAt (DB-persisted) not syncState.lastSyncAt
            // (in-memory), which is null on a fresh app launch until the first
            // scheduled sync completes.
            _connectionVerified = settings.nextcloudUrl?.isNotEmpty == true &&
                settings.nextcloudUsername?.isNotEmpty == true &&
                settings.lastSyncAt != null;
            if (settings.nextcloudPassword != null) {
              _passwordCtrl.text = settings.nextcloudPassword!;
            }
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Pending-restore banner (startup check) ──────────────────
                if (syncState.pendingRestore != null) ...[
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Newer backup on server',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer)),
                          const SizedBox(height: 4),
                          Text(
                            'Backup date: ${syncState.pendingRestore!.backupDate.toIso8601String().substring(0, 10)}',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer),
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => ref
                                      .read(nextcloudSyncProvider.notifier)
                                      .restoreFromRemote(),
                              child: const Text('Restore from server'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => ref
                                      .read(nextcloudSyncProvider.notifier)
                                      .dismissRestore(),
                              child: const Text('Dismiss'),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Connection fields ────────────────────────────────────────
                TextFormField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'https://cloud.example.com',
                  ),
                  keyboardType: TextInputType.url,
                  onChanged: (_) => _invalidateVerification(),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(labelText: 'Username'),
                  onChanged: (_) => _invalidateVerification(),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordCtrl,
                  decoration: InputDecoration(
                    labelText: 'Password / app token',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  onChanged: (_) => _invalidateVerification(),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _pathCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Upload path',
                    hintText: '/StockManager/',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),

                // ── Connection status ────────────────────────────────────────
                if (_connectionStatus != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        _connectionVerified
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 16,
                        color: _connectionVerified
                            ? Colors.green
                            : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _connectionStatus!,
                          style: TextStyle(
                            color: _connectionVerified
                                ? Colors.green
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // ── Sync status ──────────────────────────────────────────────
                if (syncState.lastSyncAt != null ||
                    syncState.status == SyncStatus.error) ...[
                  const SizedBox(height: 8),
                  Text(
                    syncState.status == SyncStatus.error
                        ? 'Auto-sync error: ${syncState.error}'
                        : syncState.status == SyncStatus.syncing
                            ? 'Syncing…'
                            : 'Last auto-sync: ${syncState.lastSyncAt!.toLocal().toIso8601String().substring(0, 16).replaceAll('T', ' ')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: syncState.status == SyncStatus.error
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // ── Actions ──────────────────────────────────────────────────
                OutlinedButton(
                  onPressed: busy ? null : _testConnection,
                  child: _isTesting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Test connection'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () =>
                          ref.read(nextcloudSyncProvider.notifier).syncNow(),
                  icon: syncState.status == SyncStatus.syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Backup to Nextcloud now'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: busy || !_connectionVerified ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirm & connect'),
                ),
                if (!_connectionVerified) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Test the connection before saving',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
