import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/stock.dart';
import '../../core/services/isin_lookup_service.dart';
import '../../core/utils/isin_validator.dart';
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
  final _currencyCtrl = TextEditingController();

  String? _selectedBrokerId;
  bool _dripEnabled = false;
  bool _isLookingUp = false;
  bool _isSaving = false;
  String? _lookupError;

  @override
  void dispose() {
    _isinCtrl.dispose();
    _symbolCtrl.dispose();
    _nameCtrl.dispose();
    _exchangeCtrl.dispose();
    _currencyCtrl.dispose();
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
    });

    final service = ref.read(isinLookupServiceProvider);
    final result = await service.lookup(isin);

    if (!mounted) return;
    setState(() {
      _isLookingUp = false;
      if (result != null) {
        _symbolCtrl.text = result.symbol;
        _nameCtrl.text = result.name;
        _exchangeCtrl.text = result.exchange;
        _currencyCtrl.text = result.currency;
      } else {
        _lookupError =
            'Could not resolve ISIN. Please fill in details manually.';
      }
    });
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
        exchange: _exchangeCtrl.text.trim().toUpperCase(),
        currency: _currencyCtrl.text.trim().toUpperCase(),
        dripEnabled: _dripEnabled,
      );
      await ref.read(stockActionsProvider).addStock(stock);
      if (mounted) router.pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brokersAsync = ref.watch(brokersProvider);

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
                    onChanged: (_) => setState(() => _lookupError = null),
                    validator: (v) =>
                        IsinValidator.errorMessage(v?.trim() ?? ''),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton(
                    onPressed: _isLookingUp ? null : _lookupIsin,
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
            TextFormField(
              controller: _currencyCtrl,
              decoration: const InputDecoration(
                  labelText: 'Currency (ISO 4217)', hintText: 'e.g. USD'),
              textCapitalization: TextCapitalization.characters,
              maxLength: 3,
              validator: (v) => v == null || v.trim().length != 3
                  ? '3-letter code required'
                  : null,
            ),
            const SizedBox(height: 8),
            brokersAsync.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('Error loading brokers: $e'),
              data: (brokers) => DropdownButtonFormField<String>(
                initialValue: _selectedBrokerId,
                decoration: const InputDecoration(labelText: 'Broker'),
                items: [
                  for (final b in brokers)
                    DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: (v) => setState(() => _selectedBrokerId = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
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
