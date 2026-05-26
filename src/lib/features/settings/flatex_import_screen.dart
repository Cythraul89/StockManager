import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/models/stock.dart';
import '../../core/models/transaction.dart';
import '../stocks/stocks_provider.dart';
import 'parsers/flatex_order_parser.dart';

enum _Phase { idle, previewing, importing, done }

class FlatexImportScreen extends ConsumerStatefulWidget {
  const FlatexImportScreen({super.key});

  @override
  ConsumerState<FlatexImportScreen> createState() =>
      _FlatexImportScreenState();
}

class _FlatexImportScreenState extends ConsumerState<FlatexImportScreen> {
  _Phase _phase = _Phase.idle;
  FlatexParseResult? _result;
  List<BrokerRow> _brokers = [];
  String? _selectedBrokerId;
  int _importedCount = 0;
  int _skippedCount = 0;
  int _duplicateCount = 0;
  String? _error;

  static const _dateFormat = 'dd.MM.yy HH:mm';

  @override
  void initState() {
    super.initState();
    _loadBrokers();
  }

  Future<void> _loadBrokers() async {
    final rows =
        await ref.read(databaseProvider).brokersDao.getAll();
    if (mounted) setState(() => _brokers = rows);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    final content = latin1.decode(bytes);
    final parsed = FlatexOrderParser.parse(content);

    if (parsed.total == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No rows found in file')),
        );
      }
      return;
    }

    setState(() {
      _result = parsed;
      _phase = _Phase.previewing;
    });
  }

  Future<void> _import() async {
    final result = _result;
    if (result == null || _selectedBrokerId == null) return;

    setState(() {
      _phase = _Phase.importing;
      _error = null;
    });

    try {
      final wasCreating = _selectedBrokerId == _kCreateFlatex;
      final brokerId = await _resolveBrokerId(_selectedBrokerId!);
      if (wasCreating) {
        // Normalize the sentinel to the real ID so subsequent "Import another
        // file" calls don't create a second broker row.
        final rows = await ref.read(databaseProvider).brokersDao.getAll();
        if (mounted) setState(() { _selectedBrokerId = brokerId; _brokers = rows; });
      }
      final db = ref.read(databaseProvider);
      final actions = ref.read(stockActionsProvider);
      const uuid = Uuid();

      var imported = 0;
      var skipped = 0;
      var duplicates = 0;

      // Group orders by ISIN to minimise DB lookups.
      final byIsin = <String, List<FlatexParsedOrder>>{};
      for (final o in result.importable) {
        byIsin.putIfAbsent(o.isin, () => []).add(o);
      }

      for (final entry in byIsin.entries) {
        final isin = entry.key;
        final orders = entry.value;

        // Find existing stock or create a placeholder.
        var stockRow = await db.stocksDao.findByIsin(isin);
        if (stockRow == null) {
          // Try ISIN lookup for symbol/currency; fall back to CSV data.
          final lookupResults = await ref
              .read(isinLookupServiceProvider)
              .lookup(isin);
          final first = lookupResults?.firstOrNull;
          final stock = Stock(
            id: uuid.v4(),
            brokerId: brokerId,
            isin: isin,
            symbol: first?.symbol ?? isin,
            name: orders.first.name,
            exchange: first?.exchange ?? '',
            // Use the order currency from the CSV, not the ISIN lookup's
            // native currency. Flatex records the execution currency (e.g. EUR
            // for Xetra/Tradegate trades). Using the lookup currency (e.g. USD
            // for US stocks) would create a mismatch between the stock currency
            // and all imported transaction currencies, breaking P&L calculations.
            currency: orders.first.currency,
            dripEnabled: false,
            assetType: first != null
                ? first.assetType
                : orders.first.assetType,
          );
          await actions.addStock(stock);
          stockRow = await db.stocksDao.findByIsin(isin);
        }

        if (stockRow == null) {
          skipped += orders.length;
          continue;
        }

        for (final o in orders) {
          final isDup = o.orderNumber.isNotEmpty
              ? await db.transactionsDao.existsByExternalRef(o.orderNumber)
              : await db.transactionsDao.existsByKey(
                  stockId: stockRow.id,
                  executedAt: o.executedAt,
                  isBuy: o.isBuy,
                  shares: o.shares,
                );
          if (isDup) {
            duplicates++;
            continue;
          }
          await actions.addTransaction(StockTransaction(
            id: uuid.v4(),
            stockId: stockRow.id,
            type: o.isBuy ? TransactionType.buy : TransactionType.sell,
            executedAt: o.executedAt,
            shares: o.shares,
            pricePerShare: o.pricePerShare,
            currency: o.currency,
            fees: Decimal.zero,
            externalRef: o.orderNumber.isNotEmpty ? o.orderNumber : null,
          ));
          imported++;
        }
      }

      if (mounted) {
        setState(() {
          _phase = _Phase.done;
          _importedCount = imported;
          _skippedCount = skipped;
          _duplicateCount = duplicates;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.previewing;
          _error = e.toString();
        });
      }
    }
  }

  Future<String> _resolveBrokerId(String id) async {
    if (id != _kCreateFlatex) return id;
    const uuid = Uuid();
    final newId = uuid.v4();
    await ref.read(databaseProvider).brokersDao.upsert(
          BrokersCompanion.insert(id: newId, name: 'Flatex'),
        );
    return newId;
  }

  static const _kCreateFlatex = '__create_flatex__';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Import from Flatex')),
      body: switch (_phase) {
        _Phase.idle => _buildIdle(theme),
        _Phase.previewing => _buildPreviewing(theme),
        _Phase.importing => const Center(child: CircularProgressIndicator()),
        _Phase.done => _buildDone(theme),
      },
    );
  }

  Widget _buildIdle(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoCard(
          theme: theme,
          text: 'Export your order history from flatex: '
              'Log in → Portfolio → Orders → Export as CSV.\n\n'
              'Supported rows: executed limit and stop-market orders, '
              'and KVG savings-plan orders (shares derived from '
              'invested amount ÷ NAV price). '
              'Fractional Bruchstücke rows and market orders without '
              'a price are skipped.\n\n'
              'Note: stop-market orders are imported with EUR currency '
              'because the Flatex CSV does not include a currency column '
              'for stop prices.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Select CSV file'),
        ),
      ],
    );
  }

  Widget _buildPreviewing(ThemeData theme) {
    final result = _result!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Summary ────────────────────────────────────────────────
        _SummaryCard(theme: theme, result: result),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.errorContainer,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ],

        if (result.importable.isEmpty) ...[
          const SizedBox(height: 24),
          Center(
            child: Text(
              'No importable transactions found.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ] else ...[
          // ── Broker selector ──────────────────────────────────────
          const SizedBox(height: 16),
          Text(
            'Assign new stocks to',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(_selectedBrokerId),
            initialValue: _selectedBrokerId,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            hint: const Text('Select broker'),
            items: [
              ..._brokers.map((b) => DropdownMenuItem(
                    value: b.id,
                    child: Text(b.name),
                  )),
              const DropdownMenuItem(
                value: _kCreateFlatex,
                child: Text('Create new broker "Flatex"'),
              ),
            ],
            onChanged: (v) => setState(() => _selectedBrokerId = v),
          ),

          // ── Transaction list ──────────────────────────────────────
          const SizedBox(height: 16),
          Text(
            'Transactions to import',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 4),
          for (final o in result.importable)
            _OrderTile(order: o, theme: theme, dateFormat: _dateFormat),

          // ── Import button ──────────────────────────────────────
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _selectedBrokerId != null ? _import : null,
            child: Text('Import ${result.importable.length} transactions'),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            _phase = _Phase.idle;
            _result = null;
            _error = null;
          }),
          child: const Text('Pick a different file'),
        ),
      ],
    );
  }

  Widget _buildDone(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Import complete',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '$_importedCount transaction${_importedCount == 1 ? '' : 's'} imported'
              '${_duplicateCount > 0 ? ', $_duplicateCount already existed' : ''}'
              '${_skippedCount > 0 ? ', $_skippedCount failed' : ''}.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => setState(() {
                _phase = _Phase.idle;
                _result = null;
              }),
              child: const Text('Import another file'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays whole numbers without a decimal point (40 not 40.00).
String _fmtShares(Decimal d) {
  if ((d % Decimal.one) == Decimal.zero) return d.truncate().toBigInt().toString();
  return d.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.theme, required this.text});
  final ThemeData theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.theme, required this.result});
  final ThemeData theme;
  final FlatexParseResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRow('Will import', '${result.importable.length}',
                theme.colorScheme.primary),
            if (result.skippedNotExecuted > 0)
              _buildRow('Skipped (not executed)', '${result.skippedNotExecuted}',
                  theme.colorScheme.onSurfaceVariant),
            if (result.skippedFractional > 0)
              _buildRow('Skipped (Bruchstücke)', '${result.skippedFractional}',
                  theme.colorScheme.onSurfaceVariant),
            if (result.skippedNoPrice > 0)
              _buildRow('Skipped (no price)', '${result.skippedNoPrice}',
                  theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile(
      {required this.order,
      required this.theme,
      required this.dateFormat});
  final FlatexParsedOrder order;
  final ThemeData theme;
  final String dateFormat;

  @override
  Widget build(BuildContext context) {
    final isBuy = order.isBuy;
    final color =
        isBuy ? Colors.green.shade700 : theme.colorScheme.error;
    final fmt = DateFormat(dateFormat);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 4),
      color: theme.colorScheme.surfaceContainerLowest,
      child: ListTile(
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Icon(
          isBuy ? Icons.arrow_downward : Icons.arrow_upward,
          color: color,
          size: 18,
        ),
        title: Text(
          order.name,
          style: theme.textTheme.bodySmall
              ?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${order.isin}  ·  ${fmt.format(order.executedAt)}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFamily: 'monospace',
          ),
        ),
        trailing: Text(
          '${_fmtShares(order.shares)} × '
          '${order.pricePerShare.toStringAsFixed(2)} ${order.currency}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}
