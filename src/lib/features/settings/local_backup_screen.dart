import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'settings_provider.dart';

class LocalBackupScreen extends ConsumerStatefulWidget {
  const LocalBackupScreen({super.key});

  @override
  ConsumerState<LocalBackupScreen> createState() => _LocalBackupScreenState();
}

class _LocalBackupScreenState extends ConsumerState<LocalBackupScreen> {
  bool _isExporting = false;
  bool _isExportingOds = false;
  bool _isImporting = false;
  String? _status;
  bool _statusIsError = false;

  Future<void> _export() async {
    setState(() {
      _isExporting = true;
      _status = null;
    });
    try {
      final file = await ref.read(backupServiceProvider).exportToZip();
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'StockManager Backup',
      );
      if (mounted) {
        setState(() {
          _status = 'Backup exported successfully.';
          _statusIsError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Export failed: $e';
          _statusIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportOds() async {
    setState(() {
      _isExportingOds = true;
      _status = null;
    });
    try {
      final file = await ref.read(backupServiceProvider).exportToOds();
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'StockManager Backup',
      );
      if (mounted) {
        setState(() {
          _status = 'ODS exported successfully.';
          _statusIsError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Export failed: $e';
          _statusIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isExportingOds = false);
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'ods'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;

    // Prefer in-memory bytes; fall back to reading from path (desktop).
    Uint8List? bytes = picked.bytes;
    if (bytes == null && picked.path != null) {
      bytes = await File(picked.path!).readAsBytes();
    }
    if (bytes == null) {
      setState(() {
        _status = 'Could not read the selected file.';
        _statusIsError = true;
      });
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Replace all data?'),
        content: const Text(
          'Importing this backup will permanently replace all current stocks, '
          'transactions and dividends with the backup contents. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _isImporting = true;
      _status = null;
    });
    try {
      await ref.read(backupServiceProvider).importFromBytes(bytes);
      if (mounted) {
        setState(() {
          _status = 'Backup imported successfully.';
          _statusIsError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Import failed: $e';
          _statusIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isExporting || _isExportingOds || _isImporting;

    return Scaffold(
      appBar: AppBar(title: const Text('Local Backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.upload_outlined),
              title: const Text('Export backup (ZIP)'),
              subtitle: const Text(
                  'Save a ZIP file containing all stocks, transactions and dividends'),
              trailing: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: busy ? null : _export,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Export backup (ODS spreadsheet)'),
              subtitle: const Text(
                  'Save an ODS spreadsheet containing all stocks, transactions and dividends'),
              trailing: _isExportingOds
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: busy ? null : _exportOds,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Import backup'),
              subtitle: const Text(
                  'Restore from a ZIP or ODS backup — replaces all current data'),
              trailing: _isImporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: busy ? null : _import,
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(
              _status!,
              style: TextStyle(
                color: _statusIsError
                    ? Theme.of(context).colorScheme.error
                    : Colors.green,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
