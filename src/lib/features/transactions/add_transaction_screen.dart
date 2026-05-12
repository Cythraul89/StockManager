import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/transaction.dart';
import '../stocks/stocks_provider.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key, required this.stockId});

  final String stockId;

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState
    extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sharesCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _feesCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();

  TransactionType _type = TransactionType.buy;
  DateTime _executedAt = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _sharesCtrl.dispose();
    _priceCtrl.dispose();
    _feesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _executedAt,
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_executedAt),
      );
      setState(() {
        _executedAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          time?.hour ?? _executedAt.hour,
          time?.minute ?? _executedAt.minute,
        );
      });
    }
  }

  Decimal? _parseDecimal(String text) {
    try {
      return Decimal.parse(text.trim().replaceAll(',', '.'));
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final shares = _parseDecimal(_sharesCtrl.text)!;
    final price = _parseDecimal(_priceCtrl.text)!;
    final fees = _parseDecimal(_feesCtrl.text) ?? Decimal.zero;

    final stockRow =
        await ref.read(databaseProvider).stocksDao.findById(widget.stockId);
    if (stockRow == null) return;

    const uuid = Uuid();
    final tx = StockTransaction(
      id: uuid.v4(),
      stockId: widget.stockId,
      type: _type,
      executedAt: _executedAt,
      shares: shares,
      pricePerShare: price,
      currency: stockRow.currency,
      fees: fees,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    setState(() => _isSaving = true);
    try {
      await ref.read(stockActionsProvider).addTransaction(tx);
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Transaction')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                    value: TransactionType.buy, label: Text('Buy')),
                ButtonSegment(
                    value: TransactionType.sell, label: Text('Sell')),
              ],
              selected: {_type},
              onSelectionChanged: (s) =>
                  setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date & Time'),
              subtitle: Text(_executedAt.toIso8601String().substring(0, 16)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _sharesCtrl,
              decoration: const InputDecoration(labelText: 'Number of shares'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (_parseDecimal(v) == null) return 'Invalid number';
                if (_parseDecimal(v)! <= Decimal.zero) {
                  return 'Must be greater than 0';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _priceCtrl,
              decoration:
                  const InputDecoration(labelText: 'Price per share'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (_parseDecimal(v) == null) return 'Invalid number';
                if (_parseDecimal(v)! <= Decimal.zero) {
                  return 'Must be greater than 0';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _feesCtrl,
              decoration:
                  const InputDecoration(labelText: 'Fees / commission'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                if (_parseDecimal(v) == null) return 'Invalid number';
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
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
