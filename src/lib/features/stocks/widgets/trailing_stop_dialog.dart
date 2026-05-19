import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TrailingStopDialog extends StatefulWidget {
  const TrailingStopDialog({super.key, this.initialPct});

  final Decimal? initialPct;

  @override
  State<TrailingStopDialog> createState() => _TrailingStopDialogState();
}

class _TrailingStopDialogState extends State<TrailingStopDialog> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.initialPct?.toStringAsFixed(1) ?? '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _ctrl.text.trim().replaceAll(',', '.');
    final value = Decimal.tryParse(raw);
    if (value == null || value <= Decimal.zero || value >= Decimal.fromInt(100)) {
      setState(() => _error = 'Enter a percentage between 0 and 100');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Trailing stop-loss'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A notification is sent when the price falls by this percentage '
            'from its peak since the alert was enabled.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            decoration: InputDecoration(
              labelText: 'Threshold (%)',
              hintText: 'e.g. 10',
              suffixText: '%',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
