import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/exchange_rate.dart';
import '../../core/utils/date_helpers.dart';
import 'settings_provider.dart';

class CurrencySettingsScreen extends ConsumerStatefulWidget {
  const CurrencySettingsScreen({super.key});

  @override
  ConsumerState<CurrencySettingsScreen> createState() =>
      _CurrencySettingsScreenState();
}

class _CurrencySettingsScreenState
    extends ConsumerState<CurrencySettingsScreen> {
  bool _isRefreshing = false;

  Future<void> _refreshRates() async {
    setState(() => _isRefreshing = true);
    try {
      final settings = await ref.read(settingsProvider.future);
      final service = ref.read(currencyServiceProvider);
      final fetched =
          await service.fetchRates(settings.preferredCurrency);
      if (fetched.isNotEmpty) {
        await ref
            .read(settingsActionsProvider)
            .cacheRates(fetched.values.toList());
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _addManualRate(String preferred) async {
    final baseCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Manual exchange rate override'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: baseCtrl,
                decoration: InputDecoration(
                    labelText: 'From currency (→ $preferred)'),
                textCapitalization: TextCapitalization.characters,
                maxLength: 3,
                validator: (v) => v == null || v.length != 3
                    ? '3-letter code required'
                    : null,
              ),
              TextFormField(
                controller: rateCtrl,
                decoration: InputDecoration(
                    labelText: 'Rate (1 X = ? $preferred)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  try {
                    final d = Decimal.parse(v.trim());
                    if (d <= Decimal.zero) return 'Must be > 0';
                  } catch (_) {
                    return 'Invalid number';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Save')),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(settingsActionsProvider).setManualRate(
            preferred,
            baseCtrl.text.trim().toUpperCase(),
            Decimal.parse(rateCtrl.text.trim()),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final ratesAsync = ref.watch(exchangeRatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Currency'),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshRates,
            tooltip: 'Refresh live rates',
          ),
        ],
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) => ratesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (rates) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Preferred display currency',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: settings.preferredCurrency,
                        items: _commonCurrencies
                            .map((c) => DropdownMenuItem(
                                value: c, child: Text(c)))
                            .toList(),
                        onChanged: (c) async {
                          if (c == null) return;
                          await ref.read(settingsActionsProvider).saveSettings(
                              settings.copyWith(preferredCurrency: c));
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Exchange rates',
                      style: Theme.of(context).textTheme.titleMedium),
                  TextButton.icon(
                    onPressed: () =>
                        _addManualRate(settings.preferredCurrency),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add override'),
                  ),
                ],
              ),
              if (rates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No rates cached. Tap refresh to fetch live rates.'),
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (int i = 0; i < rates.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _RateTile(rate: rates[i]),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static const _commonCurrencies = [
    'EUR', 'USD', 'GBP', 'CHF', 'JPY', 'CAD', 'AUD',
    'SEK', 'NOK', 'DKK', 'PLN', 'CZK', 'HUF',
  ];
}

class _RateTile extends ConsumerWidget {
  const _RateTile({required this.rate});

  final ExchangeRate rate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(
        '1 ${rate.target} = ${rate.rate.toStringAsFixed(4)} ${rate.base}',
      ),
      subtitle: Text(
        '${rate.isManualOverride ? "Manual override" : "Live"}'
        ' · ${DateHelpers.formatDateTime(rate.fetchedAt)}'
        '${rate.isStale ? " · stale" : ""}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: rate.isStale
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: rate.isManualOverride
          ? IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove override',
              onPressed: () async {
                await ref
                    .read(settingsActionsProvider)
                    .deleteRate(rate.base, rate.target);
              },
            )
          : null,
    );
  }
}
