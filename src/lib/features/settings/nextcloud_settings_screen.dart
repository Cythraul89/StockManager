import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/nextcloud_service.dart';
import 'settings_provider.dart';

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
  bool _isSyncing = false;
  bool _obscurePassword = true;
  String? _connectionStatus;

  static const _passwordKey = 'nextcloud_password';

  @override
  void dispose() {
    _urlCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _connectionStatus = null;
    });

    final service = ref.read(nextcloudServiceProvider);
    final url = _urlCtrl.text.trim();

    try {
      final certInfo = await service.fetchCertificateInfo(url);
      if (!mounted) return;

      if (certInfo != null) {
        // Self-signed cert — ask user to approve before continuing.
        final approved = await _showCertDialog(certInfo);
        if (approved != true) {
          setState(() => _connectionStatus = 'Certificate not trusted.');
          return;
        }
        await service.pinCertificate(certInfo.fingerprint);
      }

      // Verify credentials with an authenticated request.
      await service.verifyCredentials(
        serverUrl: url,
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      if (mounted) {
        setState(() =>
            _connectionStatus = 'Connection successful — credentials verified.');
      }
    } catch (e) {
      if (mounted) setState(() => _connectionStatus = 'Connection failed: $e');
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _syncToNextcloud() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSyncing = true;
      _connectionStatus = null;
    });

    try {
      final backupFile = await ref.read(backupServiceProvider).exportToZip();
      final bytes = await backupFile.readAsBytes();

      final url = _urlCtrl.text.trim();
      final username = _usernameCtrl.text.trim();
      final password = _passwordCtrl.text;
      final dir = _pathCtrl.text.trim();
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

      final settings = await ref.read(settingsProvider.future);
      await ref.read(settingsActionsProvider).saveSettings(
            settings.copyWith(lastSyncAt: DateTime.now()),
          );

      if (mounted) {
        setState(
            () => _connectionStatus = 'Backup uploaded to $remotePath.');
      }
    } catch (e) {
      if (mounted) setState(() => _connectionStatus = 'Sync failed: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final storage = ref.read(secureStorageProvider);
      await storage.write(key: _passwordKey, value: _passwordCtrl.text);

      final settings = await ref.read(settingsProvider.future);
      await ref.read(settingsActionsProvider).saveSettings(
            settings.copyWith(
              nextcloudUrl: _urlCtrl.text.trim(),
              nextcloudUsername: _usernameCtrl.text.trim(),
              nextcloudPath: _pathCtrl.text.trim(),
            ),
          );
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final busy = _isTesting || _isSaving || _isSyncing;

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
            ref.read(secureStorageProvider).read(key: _passwordKey).then((pw) {
              if (mounted && pw != null) {
                setState(() => _passwordCtrl.text = pw);
              }
            });
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'https://cloud.example.com',
                  ),
                  keyboardType: TextInputType.url,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(labelText: 'Username'),
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
                if (_connectionStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _connectionStatus!,
                    style: TextStyle(
                      color: _connectionStatus!.contains('failed') ||
                              _connectionStatus!.contains('not trusted')
                          ? Theme.of(context).colorScheme.error
                          : Colors.green,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
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
                  onPressed: busy ? null : _syncToNextcloud,
                  icon: _isSyncing
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
                  onPressed: busy ? null : _save,
                  child: _isSaving
                      ? const CircularProgressIndicator()
                      : const Text('Save'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
