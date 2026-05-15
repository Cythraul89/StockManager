import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final logServiceProvider = Provider<LogService>((ref) {
  throw UnimplementedError('logServiceProvider must be overridden');
});

class LogService {
  LogService._();

  File? _logFile;

  static Future<LogService> create() async {
    final service = LogService._();
    await service._init();
    return service;
  }

  /// Returns a no-op instance for use in tests (no file I/O).
  @visibleForTesting
  factory LogService.forTesting() => LogService._();

  Future<void> _init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/stockmanager_debug.log');
      // Start each session with a fresh file so it never grows unbounded.
      await _logFile!.writeAsString(
        '=== StockManager debug log — ${DateTime.now().toIso8601String()} ===\n',
      );
    } catch (_) {
      // If we can't open the file, logging silently no-ops.
      _logFile = null;
    }
  }

  /// Appends [message] to the log file with a timestamp prefix.
  /// Fire-and-forget — never throws.
  void log(String? message) {
    if (message == null || message.isEmpty || _logFile == null) { return; }
    final entry = '[${DateTime.now().toIso8601String()}] $message\n';
    _logFile!.writeAsString(entry, mode: FileMode.append).ignore();
  }

  /// Absolute path to the log file, for sharing.
  String get filePath => _logFile?.path ?? '';

  /// Clears the log file content.
  Future<void> clear() async {
    await _logFile?.writeAsString('');
  }
}
