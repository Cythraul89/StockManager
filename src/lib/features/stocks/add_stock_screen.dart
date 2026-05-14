import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/stock.dart';
import '../../core/services/isin_lookup_service.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/isin_validator.dart';
import '../settings/settings_provider.dart';
import 'stocks_provider.dart';

// Exposed so main.dart can override with the real service instance.
final isinLookupServiceProvider = Provider<IsinLookupService>((ref) {
  throw UnimplementedError('isinLookupServiceProvider must be overridden');
});

class AddStockScreen extends ConsumerStatefulWidget {
  const AddStockScreen({super.key});

  @override
  ConsumerState<AddStockScreen> createState() => _AddStockScreenState();
}

class _AddStockScreenState extends ConsumerState<AddStockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _isinCtrl = TextEditingController();
  final _symbolCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _exchangeCtrl = TextEditingController();

  final _currencyFieldKey = GlobalKey<FormFieldState<String>>();
  final _brokerFieldKey = GlobalKey<FormFieldState<String>>();

  String? _selectedBrokerId;
  String? _selectedCurrency;
  bool _dripEnabled = false;
  bool _isLookingUp = false;
  bool _showingPicker = false;
  bool _isSaving = false;
  String? _lookupError;
  bool _symbolUnverified = false;
  bool _brokerLoaded = false;

  static const _lastBrokerKey = 'last_used_broker_id';

  @override
  void dispose() {
    _isinCtrl.dispose();
    _symbolCtrl.dispose();
    _nameCtrl.dispose();
    _exchangeCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookupIsin() async {
    final isin = _isinCtrl.text.trim().toUpperCase();
    final error = IsinValidator.errorMessage(isin);
    if (error != null) {
      setState(() => _lookupError = error);
      return;
    }

    setState(() {
      _isLookingUp = true;
      _lookupError = null;
      _symbolUnverified = false;
    });

    final results =
        await ref.read(isinLookupServiceProvider).lookup(isin);

    if (!mounted) return;

    if (results == null || results.isEmpty) {
      setState(() {
        _isLookingUp = false;
        _lookupError =
            'Could not resolve ISIN. Please fill in details manually.';
      });
      return;
    }

    // Fetch prices for all listings in parallel
    final priceLabels = <String, String>{};
    await Future.wait(results.map((r) async {
      final q = await ref
          .read(marketDataServiceProvider)
          .fetchQuote(r.symbol, '__preview__');
      if (q != null) {
        priceLabels[r.symbol] =
            CurrencyFormatter.format(q.price, q.currency);
      }
    }));
    if (!mounted) return;

    // If multiple listings exist, let the user choose.
    IsinLookupResult chosen;
    if (results.length == 1) {
      chosen = results.first;
    } else {
      setState(() {
        _isLookingUp = false;
        _showingPicker = true;
      });
      final picked = await _showListingPicker(results, priceLabels);
      if (!mounted) return;
      setState(() {
        _showingPicker = false;
        _isLookingUp = picked != null;
      });
      if (picked == null) return;
      chosen = picked;
    }

    if (!mounted) return;
    final resolvedCurrency = chosen.currency.toUpperCase();
    setState(() {
      _isLookingUp = false;
      _symbolCtrl.text = chosen.symbol;
      _nameCtrl.text = chosen.name;
      _exchangeCtrl.text =
          chosen.exchangeName.isNotEmpty ? chosen.exchangeName : chosen.exchange;
      // Only apply the resolved currency if it's a non-empty string so the
      // user still sees the "Select currency" hint when OpenFIGI returns nothing.
      if (resolvedCurrency.isNotEmpty) {
        _selectedCurrency = resolvedCurrency;
      }
      _symbolUnverified = !priceLabels.containsKey(chosen.symbol);
    });
    if (resolvedCurrency.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _currencyFieldKey.currentState?.didChange(_selectedCurrency);
      });
    }
  }

  Future<IsinLookupResult?> _showListingPicker(
      List<IsinLookupResult> results, Map<String, String> priceLabels) {
    return showModalBottomSheet<IsinLookupResult>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Select listing',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (_, i) {
                  final r = results[i];
                  final price = priceLabels[r.symbol];
                  return ListTile(
                    title: Row(children: [
                      Text(r.symbol,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (price != null)
                        Text(price,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                    subtitle: Text([
                      if (r.exchangeName.isNotEmpty) r.exchangeName,
                      if (r.currency.isNotEmpty) r.currency,
                      if (r.securityType.isNotEmpty) r.securityType,
                      if (price == null) 'No price',
                    ].join(' · ')),
                    onTap: () => Navigator.pop(ctx, r),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    if (_selectedBrokerId == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Please select a broker')));
      return;
    }

    // Enforce 100-stock limit
    final db = ref.read(databaseProvider);
    final count = await db.stocksDao.count();
    if (count >= 100 && mounted) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Maximum of 100 stocks reached')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      const uuid = Uuid();
      final stock = Stock(
        id: uuid.v4(),
        brokerId: _selectedBrokerId!,
        isin: _isinCtrl.text.trim().toUpperCase(),
        symbol: _symbolCtrl.text.trim().toUpperCase(),
        name: _nameCtrl.text.trim(),
        exchange: _exchangeCtrl.text.trim(),
        currency: _selectedCurrency!,
        dripEnabled: _dripEnabled,
      );
      await ref.read(stockActionsProvider).addStock(stock);
      await ref.read(secureStorageProvider).write(
            key: _lastBrokerKey, value: _selectedBrokerId);
      if (mounted) router.pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brokersAsync = ref.watch(brokersStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Stock')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ISIN row with lookup button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _isinCtrl,
                    decoration: InputDecoration(
                      labelText: 'ISIN',
                      hintText: 'e.g. US0378331005',
                      errorText: _lookupError,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 12,
                    onChanged: (_) => setState(() {
                      _lookupError = null;
                      _symbolUnverified = false;
                    }),
                    validator: (v) =>
                        IsinValidator.errorMessage(v?.trim() ?? ''),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton(
                    onPressed: (_isLookingUp || _showingPicker) ? null : _lookupIsin,
                    child: _isLookingUp
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Lookup'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _symbolCtrl,
              decoration: const InputDecoration(labelText: 'Ticker symbol'),
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() => _symbolUnverified = false),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            if (_symbolUnverified) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'No price found for this symbol on Yahoo Finance. '
                      'The stock may trade under a different ticker — '
                      'check Yahoo Finance and edit the symbol above.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Company name'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _exchangeCtrl,
              decoration: const InputDecoration(labelText: 'Exchange'),
            ),
            const SizedBox(height: 8),
            FormField<String>(
              key: _currencyFieldKey,
              initialValue: _selectedCurrency,
              validator: (v) => v == null ? 'Required' : null,
              builder: (field) => InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Currency',
                  errorText: field.errorText,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCurrency,
                    hint: const Text('Select currency'),
                    isExpanded: true,
                    isDense: true,
                    items: [
                      ...CurrencyFormatter.supportedCurrencies,
                      if (_selectedCurrency != null &&
                          !CurrencyFormatter.supportedCurrencies.contains(_selectedCurrency))
                        _selectedCurrency!,
                    ]
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _selectedCurrency = v);
                      field.didChange(v);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            brokersAsync.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('Error loading brokers: $e'),
              data: (brokers) {
                if (!_brokerLoaded && brokers.isNotEmpty) {
                  _brokerLoaded = true;
                  ref.read(secureStorageProvider).read(key: _lastBrokerKey).then((id) {
                    if (mounted && id != null && brokers.any((b) => b.id == id)) {
                      setState(() => _selectedBrokerId = id);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _brokerFieldKey.currentState?.didChange(id);
                      });
                    }
                  });
                }
                return DropdownButtonFormField<String>(
                  key: _brokerFieldKey,
                  initialValue: _selectedBrokerId,
                  decoration: const InputDecoration(labelText: 'Broker'),
                  items: [
                    for (final b in brokers)
                      DropdownMenuItem(value: b.id, child: Text(b.name)),
                  ],
                  onChanged: (v) => setState(() => _selectedBrokerId = v),
                  validator: (v) => v == null ? 'Required' : null,
                );
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Dividend Reinvestment (DRIP)'),
              subtitle: const Text(
                  'Auto-create a buy transaction when a dividend is recorded'),
              value: _dripEnabled,
              onChanged: (v) => setState(() => _dripEnabled = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const CircularProgressIndicator()
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
