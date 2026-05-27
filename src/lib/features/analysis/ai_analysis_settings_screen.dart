import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/llm_service.dart';
import '../settings/settings_provider.dart';
import '../stocks/stocks_provider.dart';

const _providerMeta = [
  (
    provider: LlmProvider.claude,
    label: 'Claude (Anthropic)',
    note: 'Paid · Most capable · Prompt caching',
    console: 'console.anthropic.com',
  ),
  (
    provider: LlmProvider.groq,
    label: 'Groq',
    note: 'Free tier · Very fast',
    console: 'console.groq.com',
  ),
  (
    provider: LlmProvider.gemini,
    label: 'Google Gemini',
    note: 'Free tier · 1M tokens/day',
    console: 'aistudio.google.com',
  ),
];

class AiAnalysisSettingsScreen extends ConsumerStatefulWidget {
  const AiAnalysisSettingsScreen({super.key});

  @override
  ConsumerState<AiAnalysisSettingsScreen> createState() =>
      _AiAnalysisSettingsScreenState();
}

class _AiAnalysisSettingsScreenState
    extends ConsumerState<AiAnalysisSettingsScreen> {
  final _keyController = TextEditingController();
  bool _obscure = true;
  bool _savingKey = false;
  LlmProvider? _keyLoadedFor;
  late Future<dynamic> _settingsFuture;

  @override
  void initState() {
    super.initState();
    _settingsFuture =
        ref.read(databaseProvider).settingsDao.getSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadKey());
  }

  void _refreshSettings() {
    setState(() {
      _settingsFuture =
          ref.read(databaseProvider).settingsDao.getSettings();
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadKey() async {
    final row =
        await ref.read(databaseProvider).settingsDao.getSettings();
    final provider = LlmProvider.values.firstWhere(
      (p) => p.name == (row?.llmProvider ?? 'claude'),
      orElse: () => LlmProvider.claude,
    );
    final key = switch (provider) {
      LlmProvider.claude => row?.claudeApiKey,
      LlmProvider.groq => row?.groqApiKey,
      LlmProvider.gemini => row?.geminiApiKey,
    };
    if (mounted) {
      setState(() {
        _keyController.text = key ?? '';
        _keyLoadedFor = provider;
      });
    }
  }

  Future<void> _onProviderChanged(LlmProvider p) async {
    await ref.read(settingsActionsProvider).saveLlmProvider(p.name);
    _refreshSettings();
    await _loadKey();
  }

  Future<void> _saveKey(LlmProvider provider) async {
    setState(() => _savingKey = true);
    try {
      final key = _keyController.text.trim();
      switch (provider) {
        case LlmProvider.claude:
          await ref.read(settingsActionsProvider).saveClaudeApiKey(key);
        case LlmProvider.groq:
          await ref.read(settingsActionsProvider).saveGroqApiKey(key);
        case LlmProvider.gemini:
          await ref.read(settingsActionsProvider).saveGeminiApiKey(key);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('API key saved')));
      }
    } finally {
      if (mounted) setState(() => _savingKey = false);
    }
  }

  Future<void> _removeKey(LlmProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove API key'),
        content: const Text('Remove this API key from the device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _savingKey = true);
    try {
      switch (provider) {
        case LlmProvider.claude:
          await ref.read(settingsActionsProvider).saveClaudeApiKey(null);
        case LlmProvider.groq:
          await ref.read(settingsActionsProvider).saveGroqApiKey(null);
        case LlmProvider.gemini:
          await ref.read(settingsActionsProvider).saveGeminiApiKey(null);
      }
      _keyController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('API key removed')));
      }
    } finally {
      if (mounted) setState(() => _savingKey = false);
    }
  }

  Future<void> _saveModel(LlmProvider provider, String model) async {
    switch (provider) {
      case LlmProvider.claude:
        await ref.read(settingsActionsProvider).saveClaudeModel(model);
      case LlmProvider.groq:
        await ref.read(settingsActionsProvider).saveGroqModel(model);
      case LlmProvider.gemini:
        await ref.read(settingsActionsProvider).saveGeminiModel(model);
    }
    _refreshSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('AI Analysis')),
      body: FutureBuilder(
        future: _settingsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final row = snapshot.data;
          final activeProvider = LlmProvider.values.firstWhere(
            (p) => p.name == (row?.llmProvider ?? 'claude'),
            orElse: () => LlmProvider.claude,
          );
          final currentModel = switch (activeProvider) {
            LlmProvider.claude => row?.claudeModel ?? defaultClaudeModel,
            LlmProvider.groq => row?.groqModel ?? defaultGroqModel,
            LlmProvider.gemini => row?.geminiModel ?? defaultGeminiModel,
          };
          final models = modelsFor(activeProvider);
          final consoleName = _providerMeta
              .firstWhere((m) => m.provider == activeProvider)
              .console;

          // Keep key field in sync if provider changed externally.
          if (_keyLoadedFor != activeProvider) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _loadKey());
          }

          return ListView(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              // ── Provider picker ──────────────────────────────
              Text(
                'Provider',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 4),
              RadioGroup<LlmProvider>(
                groupValue: activeProvider,
                onChanged: (v) { if (v != null) _onProviderChanged(v); },
                child: Column(
                  children: [
                    for (final m in _providerMeta)
                      RadioListTile<LlmProvider>(
                        value: m.provider,
                        title: Text(m.label),
                        subtitle: Text(m.note),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),

              const Divider(height: 32),

              // ── API key ──────────────────────────────────────
              Text(
                'API Key',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _keyController,
                obscureText: _obscure,
                enabled: !_savingKey,
                decoration: InputDecoration(
                  hintText: 'Paste your API key…',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          _savingKey ? null : () => _saveKey(activeProvider),
                      child: _savingKey
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save key'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _savingKey
                        ? null
                        : () => _removeKey(activeProvider),
                    child: const Text('Remove'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Get your API key at $consoleName.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              const Divider(height: 32),

              // ── Model picker ─────────────────────────────────
              Text(
                'Model',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 4),
              RadioGroup<String>(
                groupValue: currentModel,
                onChanged: (v) {
                  if (!_savingKey && v != null) _saveModel(activeProvider, v);
                },
                child: Column(
                  children: [
                    for (final m in models)
                      RadioListTile<String>(
                        value: m.id,
                        title: Text(m.label),
                        subtitle: Text(m.note),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
