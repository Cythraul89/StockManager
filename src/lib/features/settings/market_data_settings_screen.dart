import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_settings.dart';
import 'settings_provider.dart';

class MarketDataSettingsScreen extends ConsumerStatefulWidget {
  const MarketDataSettingsScreen({super.key});

  @override
  ConsumerState<MarketDataSettingsScreen> createState() =>
      _MarketDataSettingsScreenState();
}

class _MarketDataSettingsScreenState
    extends ConsumerState<MarketDataSettingsScreen> {
  final _apiKeyCtrl = TextEditingController();
  bool _obscureApiKey = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    ref.read(finnhubApiKeyProvider.future).then((key) {
      if (mounted && key != null) _apiKeyCtrl.text = key;
    });
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveApiKey() async {
    setState(() => _isSaving = true);
    try {
      await ref
          .read(settingsActionsProvider)
          .saveFinnhubApiKey(_apiKeyCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API key saved')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Market Data')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Data Provider',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: RadioGroup<MarketDataProvider>(
                  groupValue: settings.marketDataProvider,
                  onChanged: (v) async {
                    if (v == null) return;
                    await ref
                        .read(settingsActionsProvider)
                        .saveSettings(
                            settings.copyWith(marketDataProvider: v));
                  },
                  child: const Column(
                    children: [
                      RadioListTile<MarketDataProvider>(
                        title: Text('Yahoo Finance'),
                        subtitle: Text('Default, no setup required'),
                        value: MarketDataProvider.yahoo,
                      ),
                      RadioListTile<MarketDataProvider>(
                        title: Text('Finnhub'),
                        subtitle: Text('Free account required, more reliable'),
                        value: MarketDataProvider.finnhub,
                      ),
                    ],
                  ),
                ),
              ),
              if (settings.marketDataProvider == MarketDataProvider.finnhub) ...[
                const SizedBox(height: 24),
                Text(
                  'Finnhub API Key',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _apiKeyCtrl,
                  decoration: InputDecoration(
                    labelText: 'Finnhub API key',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureApiKey
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () =>
                          setState(() => _obscureApiKey = !_obscureApiKey),
                    ),
                  ),
                  obscureText: _obscureApiKey,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Visit https://finnhub.io/register to get a free API key'),
                      ),
                    );
                  },
                  child: const Text('Get free API key at finnhub.io'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _isSaving ? null : _saveApiKey,
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save API key'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Note: Finnhub works best for US-listed stocks (NYSE/NASDAQ). '
                  'For international stocks the symbol must match '
                  "Finnhub's format (e.g. XETRA:ALV instead of ALV.DE).",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

