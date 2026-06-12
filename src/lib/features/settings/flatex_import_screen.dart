import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/models/exchange_rate.dart';
import '../../core/models/stock.dart';
import '../../core/models/transaction.dart';
import '../stocks/stocks_provider.dart';
import 'parsers/flatex_order_parser.dart';
import 'settings_provider.dart';

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
  int _estimatedImportedCount = 0;
  int _skippedCount = 0;
  int _duplicateCount = 0;
  String? _error;

  // Estimation state for unpriced orders
  bool _estimateEnabled = false;
  bool _estimating = false;
  List<FlatexParsedOrder> _estimatedOrders = [];
  List<String> _estimationFailed = []; // display names of orders that failed

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
      _estimateEnabled = false;
      _estimating = false;
      _estimatedOrders = [];
      _estimationFailed = [];
      _error = null;
    });
  }

  Future<void> _fetchEstimatedPrices() async {
    final result = _result;
    if (result == null || result.unpricedOrders.isEmpty) return;

    setState(() {
      _estimating = true;
      _estimatedOrders = [];
      _estimationFailed = [];
    });

    final db = ref.read(databaseProvider);
    final marketData = ref.read(marketDataServiceProvider);
    final isinLookup = ref.read(isinLookupServiceProvider);
    final currencyService = ref.read(currencyServiceProvider);
    final estimated = <FlatexParsedOrder>[];
    final failed = <String>[];

    // Exchange rates fetched at most once for the entire batch.
    Map<String, ExchangeRate>? exchangeRates;

    for (final o in result.unpricedOrders) {
      try {
        // Prefer the symbol already stored in the database — avoids an extra
        // OpenFIGI round-trip and uses the same ticker that live quotes use.
        final existingStock = await db.stocksDao.findByIsin(o.isin);

        String? symbol;
        String nativeCcy;

        if (existingStock != null && existingStock.symbol.isNotEmpty) {
          symbol = existingStock.symbol;
          // The stock currency stored at import time is the execution currency
          // (EUR for Xetra/Tradegate trades). Normalise GBp/GBX just in case.
          nativeCcy = existingStock.currency.toUpperCase();
        } else {
          final lookupResults = await isinLookup.lookup(o.isin);
          final first = lookupResults?.firstOrNull;
          symbol = first?.symbol;
          // Normalise GBp/GBX → GBP so the currency lookup works correctly
          // (Yahoo already returns the GBp price divided by 100).
          nativeCcy = (first?.currency ?? 'EUR').toUpperCase();
        }

        if (symbol == null || symbol.isEmpty) {
          failed.add(o.name);
          continue;
        }

        final price = await marketData.fetchHistoricalPrice(symbol, o.executedAt);
        if (price == null || price <= Decimal.zero) {
          failed.add(o.name);
          continue;
        }

        // The invested amount is always in EUR (Flatex KVG market orders).
        // Convert the fetched price to EUR when the security trades in another
        // currency, using current ECB rates (historic rates would be more
        // accurate, but this is an estimate the user must review regardless).
        Decimal priceInEur;
        if (nativeCcy.isEmpty || nativeCcy == 'EUR') {
          priceInEur = price;
        } else {
          exchangeRates ??= await currencyService.fetchRates('EUR');
          final rate = ExchangeRate.find(
              exchangeRates.values.toList(), nativeCcy, 'EUR');
          if (rate == null) {
            failed.add('${o.name} (no $nativeCcy→EUR rate)');
            continue;
          }
          priceInEur = rate.convert(price);
        }

        if (priceInEur <= Decimal.zero) {
          failed.add(o.name);
          continue;
        }

        final shares = (o.investedAmount.toRational() / priceInEur.toRational())
            .toDecimal(scaleOnInfinitePrecision: 8);
        if (shares <= Decimal.zero) {
          failed.add(o.name);
          continue;
        }

        estimated.add(FlatexParsedOrder(
          isin: o.isin,
          name: o.name,
          isBuy: o.isBuy,
          assetType: o.assetType,
          executedAt: o.executedAt,
          shares: shares,
          pricePerShare: priceInEur,
          currency: 'EUR',
          orderNumber: o.orderNumber,
          isEstimated: true,
        ));
      } catch (_) {
        failed.add(o.name);
      }
    }

    if (mounted) {
      setState(() {
        _estimating = false;
        _estimatedOrders = estimated;
        _estimationFailed = failed;
      });
    }
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
      var estimatedImported = 0;
      var skipped = 0;
      var duplicates = 0;

      // Merge confirmed importable rows with any estimated ones.
      final allOrders = [...result.importable, ..._estimatedOrders];

      // Group orders by ISIN to minimise DB lookups.
      final byIsin = <String, List<FlatexParsedOrder>>{};
      for (final o in allOrders) {
        byIsin.putIfAbsent(o.isin, () => []).add(o);
      }

      for (final entry in byIsin.entries) {
        final isin = entry.key;
        final orders = entry.value;

        // Find existing stock or create a placeholder.
        var stockRow = await db.stocksDao.findByIsin(isin);
        if (stockRow == null) {
          // Try ISIN lookup for symbol/currency; fall back to CSV data.
          // null = network error (still use CSV fallback — don't abort import)
          // []   = valid ISIN with no known listings (same fallback)
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
            notes: o.isEstimated
                ? 'Price estimated from historic closing price'
                : null,
          ));
          if (o.isEstimated) {
            estimatedImported++;
          } else {
            imported++;
          }
        }
      }

      if (mounted) {
        setState(() {
          _phase = _Phase.done;
          _importedCount = imported;
          _estimatedImportedCount = estimatedImported;
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
              'Supported: executed limit and stop-market orders, KVG '
              'savings-plan buys, and Bruchstücke — shares for EUR-amount '
              'rows are derived from invested amount ÷ execution price. '
              'KVG market orders without a recorded execution price can be '
              'estimated from the historic closing price.\n\n'
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
    final totalToImport = result.importable.length + _estimatedOrders.length;
    final hasAnythingToShow =
        result.importable.isNotEmpty || result.unpricedOrders.isNotEmpty;

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

        if (!hasAnythingToShow) ...[
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

          // ── Confirmed transaction list ────────────────────────────
          if (result.importable.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Transactions to import',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 4),
            for (final o in result.importable)
              _OrderTile(order: o, theme: theme, dateFormat: _dateFormat),
          ],

          // ── Unpriced orders (estimation) ──────────────────────────
          if (result.unpricedOrders.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Orders without execution price',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 4),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              child: SwitchListTile(
                dense: true,
                title: Text(
                  'Estimate from historic closing price',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${result.unpricedOrders.length} KVG market '
                  'order${result.unpricedOrders.length == 1 ? '' : 's'} — '
                  'invested amount recorded, price per share missing. '
                  'Imported as draft for your review.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                value: _estimateEnabled,
                onChanged: _estimating
                    ? null
                    : (v) {
                        setState(() => _estimateEnabled = v);
                        if (v) {
                          _fetchEstimatedPrices();
                        } else {
                          setState(() {
                            _estimatedOrders = [];
                            _estimationFailed = [];
                          });
                        }
                      },
              ),
            ),
            if (_estimating) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Fetching historic prices…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (_estimateEnabled && !_estimating) ...[
              if (_estimationFailed.isNotEmpty) ...[
                const SizedBox(height: 4),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_outlined,
                            size: 16,
                            color: theme.colorScheme.onErrorContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Could not fetch price for: '
                            '${_estimationFailed.join(', ')}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              for (final o in _estimatedOrders)
                _OrderTile(
                  order: o,
                  theme: theme,
                  dateFormat: _dateFormat,
                ),
            ],
          ],

          // ── Import button ──────────────────────────────────────
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_selectedBrokerId != null &&
                    totalToImport > 0 &&
                    !_estimating)
                ? _import
                : null,
            child: Text(
              totalToImport > 0
                  ? 'Import $totalToImport transaction${totalToImport == 1 ? '' : 's'}'
                  : 'Import',
            ),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            _phase = _Phase.idle;
            _result = null;
            _error = null;
            _estimateEnabled = false;
            _estimatedOrders = [];
            _estimationFailed = [];
          }),
          child: const Text('Pick a different file'),
        ),
      ],
    );
  }

  Widget _buildDone(ThemeData theme) {
    final total = _importedCount + _estimatedImportedCount;
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
              '$total transaction${total == 1 ? '' : 's'} imported'
              '${_estimatedImportedCount > 0 ? ' ($_estimatedImportedCount with estimated price)' : ''}'
              '${_duplicateCount > 0 ? ', $_duplicateCount already existed' : ''}'
              '${_skippedCount > 0 ? ', $_skippedCount failed' : ''}.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_estimatedImportedCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Estimated transactions are marked with '
                '"Price estimated from historic closing price" in their notes. '
                'Review and correct them in the transaction detail screen.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => setState(() {
                _phase = _Phase.idle;
                _result = null;
                _estimateEnabled = false;
                _estimatedOrders = [];
                _estimationFailed = [];
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
            if (result.unpricedOrders.isNotEmpty)
              _buildRow(
                'Can estimate (no price in CSV)',
                '${result.unpricedOrders.length}',
                theme.colorScheme.tertiary,
              ),
            if (result.skippedNotExecuted > 0)
              _buildRow('Skipped (not executed)', '${result.skippedNotExecuted}',
                  theme.colorScheme.onSurfaceVariant),
            if (result.skippedNoUnit > 0)
              _buildRow('Skipped (no unit)', '${result.skippedNoUnit}',
                  theme.colorScheme.onSurfaceVariant),
            if (result.skippedNoPrice > 0)
              _buildRow('Skipped (no price)', '${result.skippedNoPrice}',
                  theme.colorScheme.onSurfaceVariant),
            if (result.skippedOther > 0)
              _buildRow('Skipped (format issue)', '${result.skippedOther}',
                  theme.colorScheme.error),
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
  const _OrderTile({
    required this.order,
    required this.theme,
    required this.dateFormat,
  });
  final FlatexParsedOrder order;
  final ThemeData theme;
  final String dateFormat;

  @override
  Widget build(BuildContext context) {
    final isBuy = order.isBuy;
    final color = isBuy ? Colors.green.shade700 : theme.colorScheme.error;
    final fmt = DateFormat(dateFormat);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 4),
      color: order.isEstimated
          ? theme.colorScheme.tertiaryContainer.withAlpha(120)
          : theme.colorScheme.surfaceContainerLowest,
      child: ListTile(
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Icon(
          isBuy ? Icons.arrow_downward : Icons.arrow_upward,
          color: color,
          size: 18,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                order.name,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (order.isEstimated) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'estimated',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onTertiary,
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ],
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
