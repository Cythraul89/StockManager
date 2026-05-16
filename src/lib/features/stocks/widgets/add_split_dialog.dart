import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

typedef SplitResult = ({DateTime date, int from, int to});

class AddSplitDialog extends StatefulWidget {
  const AddSplitDialog({super.key});

  @override
  State<AddSplitDialog> createState() => _AddSplitDialogState();
}

class _AddSplitDialogState extends State<AddSplitDialog> {
  final _fromCtrl = TextEditingController(text: '1');
  final _toCtrl = TextEditingController();
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    final from = int.tryParse(_fromCtrl.text);
    final to = int.tryParse(_toCtrl.text);
    if (from == null || from <= 0 || to == null || to <= 0) return;
    Navigator.of(context).pop<SplitResult>((date: _date, from: from, to: to));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = int.tryParse(_fromCtrl.text) ?? 0;
    final to = int.tryParse(_toCtrl.text) ?? 0;
    final valid = from > 0 && to > 0;

    String? description;
    if (valid && from != to) {
      description = to > from
          ? '${to}:${from} forward split — each share becomes $to'
          : '${to}:${from} reverse split — $from shares become $to';
    }

    return AlertDialog(
      title: const Text('Add Stock Split'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Date',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              TextButton(
                onPressed: _pickDate,
                child: Text(DateFormat('d MMM yyyy').format(_date)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fromCtrl,
                  decoration: const InputDecoration(
                    labelText: 'From',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('→', style: TextStyle(fontSize: 18)),
              ),
              Expanded(
                child: TextField(
                  controller: _toCtrl,
                  decoration: const InputDecoration(
                    labelText: 'To',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                description,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: valid ? _submit : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
