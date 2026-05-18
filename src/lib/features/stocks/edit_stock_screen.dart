import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/asset_type.dart';
import '../../core/services/isin_lookup_service.dart';
import '../../core/utils/currency_formatter.dart';
import 'stocks_provider.dart';

class EditStockScreen extends ConsumerStatefulWidget {
  const EditStockScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<EditStockScreen> createState() => _EditStockScreenState();
}

class _EditStockScreenState extends ConsumerState<EditStockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _symbolCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _exchangeCtrl = TextEditingController();
  final _currencyFieldKey = GlobalKey<FormFieldState<String>>();
  String? _selectedCurrency;
  AssetType _assetType = AssetType.stock;
  bool _dripEnabled = false;
  bool _loaded = false;
  bool _isSaving = false;
  bool _isLookingUp = false;
  bool _showingPicker = false;

  @override
  void dispose() {
    _symbolCtrl.dispose();
    _nameCtrl.dispose();
    _exchangeCtrl.dispose();
    super.dispose();
  }

  Future<void> _researchIsin(String isin) async {
    setState(() {
      _isLookingUp = true;
    });

    final results = await ref.read(isinLookupServiceProvider).lookup(isin);

    if (!mounted) return;

    if (results == null || results.isEmpty) {
      setState(() => _isLookingUp = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No listings found for this ISIN.')),
      );
      return;
    }

    // Fetch live prices for all listings in parallel so the picker can show them.
    final priceLabels = <String, String>{};
    await Future.wait(results.map((r) async {
      final q = await ref
          .read(marketDataServiceProvider)
          .fetchQuote(r.symbol, '__preview__');
      if (q != null) {
        priceLabels[r.symbol] = CurrencyFormatter.format(q.price, q.currency);
      }
    }));
    if (!mounted) return;

    IsinLookupResult chosen;
    if (results.length == 1) {
      chosen = results.first;
      setState(() => _isLookingUp = false);
    } else {
      setState(() {
        _isLookingUp = false;
        _showingPicker = true;
      });
      final picked = await _showListingPicker(results, priceLabels);
      if (!mounted) return;
      setState(() => _showingPicker = false);
      if (picked == null) return;
      chosen = picked;
    }

    final resolvedCurrency = chosen.currency.toUpperCase();
    setState(() {
      _symbolCtrl.text = chosen.symbol;
      _nameCtrl.text = chosen.name;
      _exchangeCtrl.text =
          chosen.exchangeName.isNotEmpty ? chosen.exchangeName : chosen.exchange;
      _assetType = chosen.assetType;
      if (resolvedCurrency.isNotEmpty) {
        _selectedCurrency = resolvedCurrency;
      }
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

  // Fetches a fresh quote for the new symbol and updates the in-memory cache.
  // Must be awaited before router.pop() — using ref after disposal is unsafe.
  Future<void> _refreshPriceAfterSave(
      String stockId, String symbol, String currency) async {
    try {
      final quote = await ref
          .read(marketDataServiceProvider)
          .fetchQuote(symbol, stockId, stockCurrency: currency);
      if (quote == null) return;
      await ref.read(stockActionsProvider).cacheMarketPrice(quote);
      final notifier = ref.read(priceQuotesProvider.notifier);
      notifier.state = Map.from(notifier.state)..[stockId] = quote;
    } catch (e) {
      debugPrint('EditStock: price refresh failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(stockByIdProvider(widget.id));

    return stockAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (stock) {
        if (stock == null) {
          return Scaffold(
              appBar: AppBar(), body: const Center(child: Text('Not found')));
        }
        if (!_loaded) {
          _symbolCtrl.text = stock.symbol;
          _nameCtrl.text = stock.name;
          _exchangeCtrl.text = stock.exchange;
          _selectedCurrency = stock.currency;
          _assetType = stock.assetType;
          _dripEnabled = stock.dripEnabled;
          _loaded = true;
        }

        return Scaffold(
          appBar: AppBar(title: Text('Edit ${stock.symbol}')),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ISIN is read-only but can be used to re-lookup listings.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'ISIN'),
                        child: Text(stock.isin),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: (_isLookingUp || _showingPicker)
                          ? null
                          : () => _researchIsin(stock.isin),
                      icon: _isLookingUp
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search, size: 18),
                      label: const Text('Research'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _symbolCtrl,
                  decoration: const InputDecoration(labelText: 'Ticker symbol'),
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
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
                  textCapitalization: TextCapitalization.characters,
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
                              !CurrencyFormatter.supportedCurrencies
                                  .contains(_selectedCurrency))
                            _selectedCurrency!,
                        ]
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
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
                const SizedBox(height: 8),
                DropdownButtonFormField<AssetType>(
                  key: ValueKey<AssetType>(_assetType),
                  initialValue: _assetType,
                  decoration: const InputDecoration(
                    labelText: 'Asset type',
                    border: OutlineInputBorder(),
                  ),
                  items: AssetType.values
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _assetType = v);
                  },
                ),
                SwitchListTile(
                  title: const Text('Dividend Reinvestment (DRIP)'),
                  value: _dripEnabled,
                  onChanged: (v) => setState(() => _dripEnabled = v),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          if (!_formKey.currentState!.validate()) return;
                          setState(() => _isSaving = true);
                          final router = GoRouter.of(context);
                          try {
                            final newSymbol =
                                _symbolCtrl.text.trim().toUpperCase();
                            final newCurrency = _selectedCurrency!;
                            await ref.read(stockActionsProvider).updateStock(
                                  stock.copyWith(
                                    symbol: newSymbol,
                                    name: _nameCtrl.text.trim(),
                                    exchange: _exchangeCtrl.text
                                        .trim()
                                        .toUpperCase(),
                                    currency: newCurrency,
                                    dripEnabled: _dripEnabled,
                                    assetType: _assetType,
                                  ),
                                );
                            // When symbol or currency changed, the cached price
                            // and analyst data are stale — refresh both before
                            // popping so ref is still valid during the fetch.
                            if (newSymbol != stock.symbol ||
                                newCurrency != stock.currency) {
                              // Clear the stale price immediately so the
                              // detail screen never shows a wrong-symbol value.
                              final notifier =
                                  ref.read(priceQuotesProvider.notifier);
                              notifier.state =
                                  Map.from(notifier.state)..remove(stock.id);
                              // Await fetch — must complete before pop() disposes ref.
                              await _refreshPriceAfterSave(
                                  stock.id, newSymbol, newCurrency);
                              // Trigger analyst re-fetch via the refresh counter.
                              ref
                                  .read(analystRefreshProvider(stock.id)
                                      .notifier)
                                  .update((n) => n + 1);
                            }
                            if (mounted) router.pop();
                          } finally {
                            if (mounted) setState(() => _isSaving = false);
                          }
                        },
                  child: _isSaving
                      ? const CircularProgressIndicator()
                      : const Text('Save'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () => _confirmDelete(context, stock.symbol),
                  child: const Text('Delete stock'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, String symbol) async {
    final router = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete stock?'),
        content: Text(
            'All transactions and dividends for $symbol will also be deleted. '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(stockActionsProvider).deleteStock(widget.id);
      if (mounted) router.go('/stocks');
    }
  }
}
