import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/models/dividend.dart';
import '../../../core/utils/date_helpers.dart';

/// Dialog that lets the user review and adjust an auto-fetched paid dividend
/// before confirming it into calculations.
class ConfirmDividendDialog extends StatefulWidget {
  const ConfirmDividendDialog({super.key, required this.dividend});

  final Dividend dividend;

  @override
  State<ConfirmDividendDialog> createState() => _ConfirmDividendDialogState();
}

class _ConfirmDividendDialogState extends State<ConfirmDividendDialog> {
  late final TextEditingController _amountPerShareCtrl;
  late final TextEditingController _totalAmountCtrl;
  late final TextEditingController _whtCtrl;
  late final TextEditingController _notesCtrl;

  String? _amountError;

  @override
  void initState() {
    super.initState();
    final d = widget.dividend;
    _amountPerShareCtrl =
        TextEditingController(text: d.amountPerShare.toString());
    _totalAmountCtrl =
        TextEditingController(text: d.totalAmount?.toString() ?? '');
    _whtCtrl =
        TextEditingController(text: d.withholdingTax?.toString() ?? '');
    _notesCtrl = TextEditingController(text: d.notes ?? '');
  }

  @override
  void dispose() {
    _amountPerShareCtrl.dispose();
    _totalAmountCtrl.dispose();
    _whtCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Decimal? _parse(String text) {
    if (text.trim().isEmpty) return null;
    try {
      return Decimal.parse(text.trim().replaceAll(',', '.'));
    } catch (_) {
      return null;
    }
  }

  void _confirm() {
    final amount = _parse(_amountPerShareCtrl.text);
    if (amount == null || amount <= Decimal.zero) {
      setState(() => _amountError = 'Enter a positive number');
      return;
    }

    final confirmed = widget.dividend.copyWith(
      amountPerShare: amount,
      totalAmount: _parse(_totalAmountCtrl.text),
      withholdingTax: _parse(_whtCtrl.text),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      confirmed: true,
    );
    Navigator.of(context).pop(confirmed);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dividend;
    return AlertDialog(
      title: const Text('Confirm dividend'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment date: ${DateHelpers.formatDate(d.date)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountPerShareCtrl,
              decoration: InputDecoration(
                labelText: 'Amount per share (${d.currency})',
                errorText: _amountError,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) {
                if (_amountError != null) {
                  setState(() => _amountError = null);
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _totalAmountCtrl,
              decoration: InputDecoration(
                labelText: 'Total received (${d.currency}, optional)',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _whtCtrl,
              decoration: InputDecoration(
                labelText: 'Withholding tax (${d.currency}, optional)',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
