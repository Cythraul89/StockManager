import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  String? _selectedCurrency;
  bool _dripEnabled = false;
  bool _loaded = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _symbolCtrl.dispose();
    _nameCtrl.dispose();
    _exchangeCtrl.dispose();
    super.dispose();
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
                // ISIN is read-only after save
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'ISIN'),
                  child: Text(stock.isin),
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
                DropdownButtonFormField<String>(
                  initialValue: _selectedCurrency,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: [
                    ...CurrencyFormatter.supportedCurrencies,
                    if (_selectedCurrency != null &&
                        !CurrencyFormatter.supportedCurrencies.contains(_selectedCurrency))
                      _selectedCurrency!,
                  ]
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedCurrency = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                const SizedBox(height: 8),
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
                            await ref.read(stockActionsProvider).updateStock(
                                  stock.copyWith(
                                    symbol: _symbolCtrl.text.trim().toUpperCase(),
                                    name: _nameCtrl.text.trim(),
                                    exchange: _exchangeCtrl.text.trim().toUpperCase(),
                                    currency: _selectedCurrency!,
                                    dripEnabled: _dripEnabled,
                                  ),
                                );
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
