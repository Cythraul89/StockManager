import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';

class ManualPriceDialog extends StatefulWidget {
  const ManualPriceDialog({super.key, required this.initialCurrency});

  final String initialCurrency;

  @override
  State<ManualPriceDialog> createState() => _ManualPriceDialogState();
}

class _ManualPriceDialogState extends State<ManualPriceDialog> {
  final _controller = TextEditingController();
  late String _currency;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _currency = widget.initialCurrency;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set manual price'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Price',
              errorText: _errorText,
            ),
            autofocus: true,
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _currency,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: CurrencyFormatter.supportedCurrencies
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _currency = v);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final price = Decimal.tryParse(_controller.text.trim());
            if (price == null || price.compareTo(Decimal.zero) <= 0) {
              setState(() => _errorText = 'Enter a positive number');
              return;
            }
            Navigator.of(context).pop((currency: _currency, price: price));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
