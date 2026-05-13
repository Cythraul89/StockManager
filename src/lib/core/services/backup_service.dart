import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupService {
  const BackupService(this._db);

  final AppDatabase _db;

  static const _formatVersion = 1;

  // Serialises the entire portfolio to a ZIP file in the temp directory.
  // Returns the file so the caller can share/save it.
  Future<File> exportToZip() async {
    final brokers = await _db.brokersDao.getAll();
    final stocks = await _db.stocksDao.getAll();
    final transactions = await _db.transactionsDao.getAll();
    final dividends = await _db.dividendsDao.getAll();
    final splits = await _db.stocksDao.getAllSplits();

    final archive = Archive();

    void addJson(String name, Object data) {
      final bytes = utf8.encode(jsonEncode(data));
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addJson('meta.json', {
      'version': _formatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'schemaVersion': _db.schemaVersion,
    });

    addJson('brokers.json', [
      for (final b in brokers)
        {'id': b.id, 'name': b.name, 'notes': b.notes},
    ]);

    addJson('stocks.json', [
      for (final s in stocks)
        {
          'id': s.id,
          'brokerId': s.brokerId,
          'isin': s.isin,
          'symbol': s.symbol,
          'name': s.name,
          'exchange': s.exchange,
          'currency': s.currency,
          'dripEnabled': s.dripEnabled,
        },
    ]);

    addJson('transactions.json', [
      for (final t in transactions)
        {
          'id': t.id,
          'stockId': t.stockId,
          'type': t.type,
          'executedAt': t.executedAt.toUtc().toIso8601String(),
          'shares': t.shares.toString(),
          'pricePerShare': t.pricePerShare.toString(),
          'currency': t.currency,
          'fees': t.fees.toString(),
          'notes': t.notes,
        },
    ]);

    addJson('dividends.json', [
      for (final d in dividends)
        {
          'id': d.id,
          'stockId': d.stockId,
          'type': d.type,
          'date': d.date.toUtc().toIso8601String(),
          'amountPerShare': d.amountPerShare.toString(),
          'totalAmount': d.totalAmount?.toString(),
          'currency': d.currency,
          'withholdingTax': d.withholdingTax?.toString(),
          'notes': d.notes,
        },
    ]);

    addJson('stock_splits.json', [
      for (final s in splits)
        {
          'id': s.id,
          'stockId': s.stockId,
          'date': s.date.toUtc().toIso8601String(),
          'fromShares': s.fromShares,
          'toShares': s.toShares,
        },
    ]);

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) throw const BackupException('Failed to create ZIP archive');

    final tempDir = await getTemporaryDirectory();
    final dateStr = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final file = File(p.join(tempDir.path, 'stockmanager_backup_$dateStr.zip'));
    await file.writeAsBytes(zipBytes);
    return file;
  }

  // Replaces all portfolio data with the contents of [bytes] (a ZIP archive).
  Future<void> importFromBytes(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    List<int> fileBytes(String name) {
      final f = archive.findFile(name);
      if (f == null) throw BackupException('Invalid backup: missing $name');
      return f.content as List<int>;
    }

    final meta = jsonDecode(utf8.decode(fileBytes('meta.json'))) as Map<String, dynamic>;
    final version = meta['version'] as int? ?? 0;
    if (version != _formatVersion) {
      throw BackupException('Unsupported backup version $version (expected $_formatVersion)');
    }

    final brokersData =
        (jsonDecode(utf8.decode(fileBytes('brokers.json'))) as List).cast<Map<String, dynamic>>();
    final stocksData =
        (jsonDecode(utf8.decode(fileBytes('stocks.json'))) as List).cast<Map<String, dynamic>>();
    final txData =
        (jsonDecode(utf8.decode(fileBytes('transactions.json'))) as List).cast<Map<String, dynamic>>();
    final divData =
        (jsonDecode(utf8.decode(fileBytes('dividends.json'))) as List).cast<Map<String, dynamic>>();
    final splitsData =
        (jsonDecode(utf8.decode(fileBytes('stock_splits.json'))) as List).cast<Map<String, dynamic>>();

    await _db.transaction(() async {
      // Clear in reverse FK order so constraints are satisfied.
      await _db.customStatement('DELETE FROM dividends');
      await _db.customStatement('DELETE FROM transactions');
      await _db.customStatement('DELETE FROM stock_splits');
      await _db.customStatement('DELETE FROM stocks');
      await _db.customStatement('DELETE FROM brokers');

      for (final b in brokersData) {
        await _db.brokersDao.upsert(BrokersCompanion.insert(
          id: b['id'] as String,
          name: b['name'] as String,
          notes: Value(b['notes'] as String?),
        ));
      }

      for (final s in stocksData) {
        await _db.stocksDao.upsert(StocksCompanion.insert(
          id: s['id'] as String,
          brokerId: s['brokerId'] as String,
          isin: s['isin'] as String,
          symbol: s['symbol'] as String,
          name: s['name'] as String,
          exchange: s['exchange'] as String,
          currency: s['currency'] as String,
          dripEnabled: Value(s['dripEnabled'] as bool? ?? false),
        ));
      }

      for (final t in txData) {
        await _db.transactionsDao.insert(TransactionsCompanion.insert(
          id: t['id'] as String,
          stockId: t['stockId'] as String,
          type: t['type'] as String,
          executedAt: DateTime.parse(t['executedAt'] as String),
          shares: Decimal.parse(t['shares'] as String),
          pricePerShare: Decimal.parse(t['pricePerShare'] as String),
          currency: t['currency'] as String,
          fees: Value(Decimal.parse((t['fees'] as String?) ?? '0')),
          notes: Value(t['notes'] as String?),
        ));
      }

      for (final d in divData) {
        await _db.dividendsDao.insert(DividendsCompanion.insert(
          id: d['id'] as String,
          stockId: d['stockId'] as String,
          type: d['type'] as String,
          date: DateTime.parse(d['date'] as String),
          amountPerShare: Decimal.parse(d['amountPerShare'] as String),
          totalAmount: Value(d['totalAmount'] != null
              ? Decimal.parse(d['totalAmount'] as String)
              : null),
          currency: d['currency'] as String,
          withholdingTax: Value(d['withholdingTax'] != null
              ? Decimal.parse(d['withholdingTax'] as String)
              : null),
          notes: Value(d['notes'] as String?),
        ));
      }

      for (final s in splitsData) {
        await _db.stocksDao.upsertSplit(StockSplitsCompanion.insert(
          id: s['id'] as String,
          stockId: s['stockId'] as String,
          date: DateTime.parse(s['date'] as String),
          fromShares: s['fromShares'] as int,
          toShares: s['toShares'] as int,
        ));
      }
    });
  }
}
