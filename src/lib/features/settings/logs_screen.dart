import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/log_service.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  List<String>? _lines;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lines = await ref.read(logServiceProvider).readRecent(lines: 300);
    if (mounted) setState(() => _lines = lines);
  }

  Future<void> _export() async {
    final logService = ref.read(logServiceProvider);
    final path = logService.filePath;
    if (path.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No log file yet')),
        );
      }
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], subject: 'StockManager debug log'),
      );
    } catch (_) {
      // File sharing is not available on this platform (e.g., Linux desktop
      // without an XDG portal). Show the path so the user can open it manually.
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Log file location'),
          content: SelectableText(path),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: path));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Copy path'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    if (!mounted) return;
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear logs'),
        content: const Text('Delete all log entries?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await ref.read(logServiceProvider).clear();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logs cleared')),
      );
    }
  }

  Color _lineColor(BuildContext context, String line) {
    if (line.contains('[ERROR]')) return Theme.of(context).colorScheme.error;
    if (line.contains('[WARN ]')) return Theme.of(context).colorScheme.tertiary;
    return Theme.of(context).colorScheme.onSurface;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Export',
            onPressed: _export,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: _clear,
          ),
        ],
      ),
      body: _lines == null
          ? const Center(child: CircularProgressIndicator())
          : _lines!.isEmpty
              ? Center(
                  child: Text(
                    'No log entries yet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  itemCount: _lines!.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      _lines![i],
                      style: TextStyle(
                        fontSize: 11,
                        color: _lineColor(context, _lines![i]),
                      ),
                    ),
                  ),
                ),
    );
  }
}
