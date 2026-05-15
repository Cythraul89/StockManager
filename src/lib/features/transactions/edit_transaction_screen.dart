import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/transaction.dart';
import '../stocks/stocks_provider.dart';

class EditTransactionScreen extends ConsumerStatefulWidget {
  const EditTransactionScreen({
    super.key,
    required this.stockId,
    required this.transactionId,
  });

  final String stockId;
  final String transactionId;

  @override
  ConsumerState<EditTransactionScreen> createState() =>
      _EditTransactionScreenState();
}

class _EditTransactionScreenState
    extends ConsumerState<EditTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sharesCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _feesCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  TransactionType _type = TransactionType.buy;
  DateTime _executedAt = DateTime.now();
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _initialised = false;

  @override
  void dispose() {
    _sharesCtrl.dispose();
    _priceCtrl.dispose();
    _feesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _populateFrom(StockTransaction tx) {
    if (_initialised) return;
    _initialised = true;
    _type = tx.type;
    _executedAt = tx.executedAt;
    _sharesCtrl.text = tx.shares.toString();
    _priceCtrl.text = tx.pricePerShare.toString();
    _feesCtrl.text = tx.fees.toString();
    _notesCtrl.text = tx.notes ?? '';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _executedAt,
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_executedAt),
    );
    if (!mounted) return;
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

  Decimal? _parseDecimal(String text) {
    try {
      return Decimal.parse(text.trim().replaceAll(',', '.'));
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(StockTransaction original) async {
    if (!_formKey.currentState!.validate()) return;

    final router = GoRouter.of(context);
    final shares = _parseDecimal(_sharesCtrl.text)!;
    final price = _parseDecimal(_priceCtrl.text)!;
    final fees = _parseDecimal(_feesCtrl.text) ?? Decimal.zero;

    final updated = original.copyWith(
      type: _type,
      executedAt: _executedAt,
      shares: shares,
      pricePerShare: price,
      fees: fees,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    setState(() => _isSaving = true);
    try {
      await ref.read(stockActionsProvider).updateTransaction(updated);
      if (mounted) router.pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final router = GoRouter.of(context);
    setState(() => _isDeleting = true);
    try {
      await ref
          .read(stockActionsProvider)
          .deleteTransaction(widget.transactionId);
      if (mounted) router.pop();
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: ref
          .read(databaseProvider)
          .transactionsDao
          .findById(widget.transactionId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final tx = snapshot.data;
        if (tx == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit Transaction')),
            body: const Center(child: Text('Transaction not found')),
          );
        }

        final original = StockTransaction(
          id: tx.id,
          stockId: tx.stockId,
          type: TransactionType.values.byName(tx.type),
          executedAt: tx.executedAt,
          shares: tx.shares,
          pricePerShare: tx.pricePerShare,
          currency: tx.currency,
          fees: tx.fees,
          notes: tx.notes,
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _populateFrom(original));
        });

        final busy = _isSaving || _isDeleting;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Edit Transaction'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: busy ? null : _delete,
              ),
            ],
          ),
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
                  subtitle: Text(
                      _executedAt.toIso8601String().substring(0, 16)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: busy ? null : _pickDate,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _sharesCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Number of shares'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
                  controller: _notesCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : () => _save(original),
                  child: _isSaving
                      ? const CircularProgressIndicator()
                      : const Text('Save'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
