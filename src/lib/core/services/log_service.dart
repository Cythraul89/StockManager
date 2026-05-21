import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final logServiceProvider = Provider<LogService>((ref) {
  throw UnimplementedError('logServiceProvider must be overridden');
});

class LogService {
  LogService._();

  File? _file;
  IOSink? _sink;

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
      _file = File('${dir.path}/stockmanager_debug.log');
      // Truncate at session start so the file never grows unbounded.
      _sink = _file!.openWrite();
      _sink!.writeln(
        '=== StockManager debug log — ${DateTime.now().toIso8601String()} ===',
      );
    } catch (_) {
      _file = null;
      _sink = null;
    }
  }

  /// Appends [message] to the log file with a timestamp prefix.
  /// IOSink serialises concurrent writes so entries never interleave.
  void log(String? message) {
    if (message == null || message.isEmpty || _sink == null) { return; }
    _sink!.writeln('[${DateTime.now().toIso8601String()}] $message');
  }

  /// Absolute path to the log file, for sharing.
  String get filePath => _file?.path ?? '';

  /// Returns the last [lines] lines of the log file.
  Future<List<String>> readRecent({int lines = 300}) async {
    if (_file == null || !await _file!.exists()) return [];
    await _sink?.flush();
    final all = await _file!.readAsLines();
    return all.length <= lines ? all : all.sublist(all.length - lines);
  }

  /// Clears the log file content and writes a fresh session header.
  Future<void> clear() async {
    await _sink?.flush();
    await _sink?.close();
    if (_file != null) {
      _sink = _file!.openWrite();
      _sink!.writeln(
        '=== StockManager debug log — ${DateTime.now().toIso8601String()} ===',
      );
    }
  }
}
