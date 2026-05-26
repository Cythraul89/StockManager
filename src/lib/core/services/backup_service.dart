import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

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
  static const _nsTable = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
  static const _nsText = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';

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
          'externalRef': t.externalRef,
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
    await tempDir.create(recursive: true);
    final dateStr = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final file = File(p.join(tempDir.path, 'stockmanager_backup_$dateStr.zip'));
    await file.writeAsBytes(zipBytes);
    return file;
  }

  // Serialises the entire portfolio to an ODS spreadsheet in the temp directory.
  Future<File> exportToOds() async {
    final brokers = await _db.brokersDao.getAll();
    final stocks = await _db.stocksDao.getAll();
    final transactions = await _db.transactionsDao.getAll();
    final dividends = await _db.dividendsDao.getAll();
    final splits = await _db.stocksDao.getAllSplits();

    final content = StringBuffer();
    content.write('<?xml version="1.0" encoding="UTF-8"?>');
    content.write('<office:document-content'
        ' xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"'
        ' xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"'
        ' xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"'
        ' office:version="1.3">');
    content.write('<office:body><office:spreadsheet>');

    content.write('<table:table table:name="brokers">');
    content.write(_odsRow(['id', 'name', 'notes']));
    for (final b in brokers) {
      content.write(_odsRow([b.id, b.name, b.notes]));
    }
    content.write('</table:table>');

    content.write('<table:table table:name="stocks">');
    content.write(_odsRow(
        ['id', 'brokerId', 'isin', 'symbol', 'name', 'exchange', 'currency', 'dripEnabled']));
    for (final s in stocks) {
      content.write(_odsRow([
        s.id, s.brokerId, s.isin, s.symbol, s.name, s.exchange, s.currency,
        s.dripEnabled.toString(),
      ]));
    }
    content.write('</table:table>');

    content.write('<table:table table:name="transactions">');
    content.write(_odsRow([
      'id', 'stockId', 'type', 'executedAt', 'shares', 'pricePerShare', 'currency', 'fees', 'notes', 'externalRef',
    ]));
    for (final t in transactions) {
      content.write(_odsRow([
        t.id, t.stockId, t.type,
        t.executedAt.toUtc().toIso8601String(),
        t.shares.toString(), t.pricePerShare.toString(),
        t.currency, t.fees.toString(), t.notes, t.externalRef,
      ]));
    }
    content.write('</table:table>');

    content.write('<table:table table:name="dividends">');
    content.write(_odsRow([
      'id', 'stockId', 'type', 'date', 'amountPerShare', 'totalAmount', 'currency',
      'withholdingTax', 'notes',
    ]));
    for (final d in dividends) {
      content.write(_odsRow([
        d.id, d.stockId, d.type,
        d.date.toUtc().toIso8601String(),
        d.amountPerShare.toString(), d.totalAmount?.toString(),
        d.currency, d.withholdingTax?.toString(), d.notes,
      ]));
    }
    content.write('</table:table>');

    content.write('<table:table table:name="stock_splits">');
    content.write(_odsRow(['id', 'stockId', 'date', 'fromShares', 'toShares']));
    for (final s in splits) {
      content.write(_odsRow([
        s.id, s.stockId,
        s.date.toUtc().toIso8601String(),
        s.fromShares.toString(), s.toShares.toString(),
      ]));
    }
    content.write('</table:table>');

    content.write('</office:spreadsheet></office:body></office:document-content>');

    const manifest = '<?xml version="1.0" encoding="UTF-8"?>'
        '<manifest:manifest'
        ' xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"'
        ' manifest:version="1.3">'
        '<manifest:file-entry manifest:full-path="/"'
        ' manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>'
        '<manifest:file-entry manifest:full-path="content.xml"'
        ' manifest:media-type="text/xml"/>'
        '</manifest:manifest>';

    final archive = Archive();

    final mimetypeBytes =
        utf8.encode('application/vnd.oasis.opendocument.spreadsheet');
    final mimetypeFile =
        ArchiveFile('mimetype', mimetypeBytes.length, mimetypeBytes);
    mimetypeFile.compress = false;
    archive.addFile(mimetypeFile);

    final manifestBytes = utf8.encode(manifest);
    archive.addFile(
        ArchiveFile('META-INF/manifest.xml', manifestBytes.length, manifestBytes));

    final contentBytes = utf8.encode(content.toString());
    archive.addFile(ArchiveFile('content.xml', contentBytes.length, contentBytes));

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) throw const BackupException('Failed to create ODS file');

    final tempDir = await getTemporaryDirectory();
    await tempDir.create(recursive: true);
    final dateStr = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final file = File(p.join(tempDir.path, 'stockmanager_backup_$dateStr.ods'));
    await file.writeAsBytes(zipBytes);
    return file;
  }

  // Replaces all portfolio data with the contents of [bytes].
  // Auto-detects ZIP backup (contains meta.json) or ODS (contains content.xml).
  Future<void> importFromBytes(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.findFile('meta.json') != null) {
      await _importZip(archive);
    } else if (archive.findFile('content.xml') != null) {
      await _importOds(archive);
    } else {
      throw const BackupException('Unrecognised file format');
    }
  }

  Future<void> _importZip(Archive archive) async {
    List<int> fileBytes(String name) {
      final f = archive.findFile(name);
      if (f == null) throw BackupException('Invalid backup: missing $name');
      return f.content as List<int>;
    }

    final meta =
        jsonDecode(utf8.decode(fileBytes('meta.json'))) as Map<String, dynamic>;
    final version = meta['version'] as int? ?? 0;
    if (version != _formatVersion) {
      throw BackupException(
          'Unsupported backup version $version (expected $_formatVersion)');
    }

    final brokersData = (jsonDecode(utf8.decode(fileBytes('brokers.json'))) as List)
        .cast<Map<String, dynamic>>();
    final stocksData = (jsonDecode(utf8.decode(fileBytes('stocks.json'))) as List)
        .cast<Map<String, dynamic>>();
    final txData =
        (jsonDecode(utf8.decode(fileBytes('transactions.json'))) as List)
            .cast<Map<String, dynamic>>();
    final divData = (jsonDecode(utf8.decode(fileBytes('dividends.json'))) as List)
        .cast<Map<String, dynamic>>();
    final splitsData =
        (jsonDecode(utf8.decode(fileBytes('stock_splits.json'))) as List)
            .cast<Map<String, dynamic>>();

    await _restore(brokersData, stocksData, txData, divData, splitsData);
  }

  Future<void> _importOds(Archive archive) async {
    final f = archive.findFile('content.xml');
    if (f == null) throw const BackupException('Invalid ODS: missing content.xml');
    final doc = XmlDocument.parse(utf8.decode(f.content as List<int>));

    List<List<String>> readSheet(String sheetName) {
      XmlElement? sheet;
      for (final t in doc.findAllElements('table', namespace: _nsTable)) {
        final n = t.getAttribute('name', namespace: _nsTable) ??
            t.getAttribute('name');
        if (n == sheetName) {
          sheet = t;
          break;
        }
      }
      if (sheet == null) {
        throw BackupException('Invalid ODS: missing sheet "$sheetName"');
      }
      final rows = <List<String>>[];
      for (final row in sheet.findElements('table-row', namespace: _nsTable)) {
        final cells = <String>[];
        for (final cell
            in row.findElements('table-cell', namespace: _nsTable)) {
          final ps = cell.findElements('p', namespace: _nsText);
          cells.add(ps.isEmpty ? '' : ps.first.innerText);
        }
        rows.add(cells);
      }
      return rows;
    }

    String col(List<String> row, int i) => i < row.length ? row[i] : '';
    String? optCol(List<String> row, int i) {
      final v = col(row, i);
      return v.isEmpty ? null : v;
    }

    final brokersRows = readSheet('brokers').skip(1).toList();
    final stocksRows = readSheet('stocks').skip(1).toList();
    final txRows = readSheet('transactions').skip(1).toList();
    final divRows = readSheet('dividends').skip(1).toList();
    final splitsRows = readSheet('stock_splits').skip(1).toList();

    final brokersData = [
      for (final r in brokersRows)
        {'id': col(r, 0), 'name': col(r, 1), 'notes': optCol(r, 2)},
    ];
    final stocksData = [
      for (final r in stocksRows)
        {
          'id': col(r, 0),
          'brokerId': col(r, 1),
          'isin': col(r, 2),
          'symbol': col(r, 3),
          'name': col(r, 4),
          'exchange': col(r, 5),
          'currency': col(r, 6),
          'dripEnabled': col(r, 7) == 'true',
        },
    ];
    final txData = [
      for (final r in txRows)
        {
          'id': col(r, 0),
          'stockId': col(r, 1),
          'type': col(r, 2),
          'executedAt': col(r, 3),
          'shares': col(r, 4),
          'pricePerShare': col(r, 5),
          'currency': col(r, 6),
          'fees': col(r, 7).isEmpty ? '0' : col(r, 7),
          'notes': optCol(r, 8),
          'externalRef': optCol(r, 9),
        },
    ];
    final divData = [
      for (final r in divRows)
        {
          'id': col(r, 0),
          'stockId': col(r, 1),
          'type': col(r, 2),
          'date': col(r, 3),
          'amountPerShare': col(r, 4),
          'totalAmount': optCol(r, 5),
          'currency': col(r, 6),
          'withholdingTax': optCol(r, 7),
          'notes': optCol(r, 8),
        },
    ];
    final splitsData = [
      for (final r in splitsRows)
        {
          'id': col(r, 0),
          'stockId': col(r, 1),
          'date': col(r, 2),
          'fromShares': int.tryParse(col(r, 3)) ?? 0,
          'toShares': int.tryParse(col(r, 4)) ?? 0,
        },
    ];

    await _restore(brokersData, stocksData, txData, divData, splitsData);
  }

  Future<void> _restore(
    List<Map<String, dynamic>> brokersData,
    List<Map<String, dynamic>> stocksData,
    List<Map<String, dynamic>> txData,
    List<Map<String, dynamic>> divData,
    List<Map<String, dynamic>> splitsData,
  ) async {
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
          fees: Value(Decimal.parse(t['fees']?.toString() ?? '0')),
          notes: Value(t['notes'] as String?),
          externalRef: Value(t['externalRef'] as String?),
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
          fromShares: (s['fromShares'] as num).toInt(),
          toShares: (s['toShares'] as num).toInt(),
        ));
      }
    });
  }

  static String _odsRow(List<String?> cells) {
    final buf = StringBuffer('<table:table-row>');
    for (final c in cells) {
      buf.write('<table:table-cell office:value-type="string">'
          '<text:p>${_escXml(c ?? '')}</text:p>'
          '</table:table-cell>');
    }
    buf.write('</table:table-row>');
    return buf.toString();
  }

  static String _escXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
