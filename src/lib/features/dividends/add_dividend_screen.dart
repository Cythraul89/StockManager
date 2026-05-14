import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/dividend.dart';
import '../stocks/stocks_provider.dart';

class AddDividendScreen extends ConsumerStatefulWidget {
  const AddDividendScreen({super.key, required this.stockId});

  final String stockId;

  @override
  ConsumerState<AddDividendScreen> createState() => _AddDividendScreenState();
}

class _AddDividendScreenState extends ConsumerState<AddDividendScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountPerShareCtrl = TextEditingController();
  final _totalAmountCtrl = TextEditingController();
  final _whtCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DividendType _type = DividendType.paid;
  DateTime _date = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _amountPerShareCtrl.dispose();
    _totalAmountCtrl.dispose();
    _whtCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Decimal? _parseDecimal(String text) {
    if (text.trim().isEmpty) return null;
    try {
      return Decimal.parse(text.trim().replaceAll(',', '.'));
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final stockRow =
        await ref.read(databaseProvider).stocksDao.findById(widget.stockId);
    if (stockRow == null) return;

    const uuid = Uuid();
    final div = Dividend(
      id: uuid.v4(),
      stockId: widget.stockId,
      type: _type,
      date: _date,
      amountPerShare: _parseDecimal(_amountPerShareCtrl.text)!,
      totalAmount: _type == DividendType.paid
          ? _parseDecimal(_totalAmountCtrl.text)
          : null,
      currency: stockRow.currency,
      withholdingTax: _parseDecimal(_whtCtrl.text),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    setState(() => _isSaving = true);
    try {
      await ref.read(stockActionsProvider).addDividend(div);
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Dividend')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<DividendType>(
              segments: const [
                ButtonSegment(
                    value: DividendType.paid, label: Text('Paid')),
                ButtonSegment(
                    value: DividendType.expected, label: Text('Expected')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_type == DividendType.paid
                  ? 'Payment date'
                  : 'Expected date'),
              subtitle: Text(_date.toIso8601String().substring(0, 10)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _amountPerShareCtrl,
              decoration: const InputDecoration(
                  labelText: 'Amount per share'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (_parseDecimal(v) == null) return 'Invalid number';
                return null;
              },
            ),
            if (_type == DividendType.paid) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _totalAmountCtrl,
                decoration: const InputDecoration(
                    labelText: 'Total amount received (optional)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (_parseDecimal(v) == null) return 'Invalid number';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _whtCtrl,
                decoration: const InputDecoration(
                    labelText: 'Withholding tax (optional)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (_parseDecimal(v) == null) return 'Invalid number';
                  return null;
                },
              ),
            ],
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
