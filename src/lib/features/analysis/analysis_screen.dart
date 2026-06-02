import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/analyst_data.dart';
import '../../core/utils/decimal_math.dart';
import '../dashboard/dashboard_provider.dart';
import '../settings/settings_provider.dart';
import '../stocks/stocks_provider.dart';
import 'analysis_provider.dart';

// Aggregates analyst buy/strong_buy recommendations for currently-held stocks.
// Moving this into a Provider instead of doing ref.watch in a build loop avoids
// unpredictable subscription churn when the items list changes between frames.
// Each analystDataProvider lookup triggers a live (rate-limited) market-data
// round-trip, so cap how many we fan out for this summary panel. We pick the
// largest holdings by value, which are the most material to a buy/sell view;
// recommendations for smaller positions still surface on each stock's detail
// screen. Typical portfolios stay well under this cap.
const _kMaxAnalystLookups = 20;

// Upside (% to analyst target) for a held position, or null when it can't be
// computed. Mirrors the guard used in _BuyTile so sort order matches display.
Decimal? _upsideOf(StockSummaryItem item, AnalystData analyst) {
  if (!item.hasPrice ||
      !item.currentPrice.isPositive ||
      !analyst.targetMeanPrice.isPositive) {
    return null;
  }
  return analyst.targetMeanPrice.percentChangeFrom(item.currentPrice);
}

final _topBuysProvider =
    Provider<List<({StockSummaryItem item, AnalystData analyst})>>((ref) {
  final items = ref.watch(portfolioSummaryProvider).value?.stockItems ?? [];
  // Only held positions, largest first, capped to bound market-data fan-out.
  final held = items.where((i) => i.sharesHeld.isPositive).toList()
    ..sort((a, b) => b.currentValue.compareTo(a.currentValue));
  final candidates = held.take(_kMaxAnalystLookups);

  final buys = <({StockSummaryItem item, AnalystData analyst})>[];
  for (final item in candidates) {
    final analyst = ref.watch(analystDataProvider(item.stock.id)).value;
    if (analyst == null) continue;
    final key = analyst.recommendationKey?.toLowerCase();
    if (key == 'strong_buy' || key == 'buy') {
      buys.add((item: item, analyst: analyst));
    }
  }
  buys.sort((a, b) {
    final aStrong = a.analyst.recommendationKey?.toLowerCase() == 'strong_buy';
    final bStrong = b.analyst.recommendationKey?.toLowerCase() == 'strong_buy';
    if (aStrong != bStrong) return aStrong ? -1 : 1;
    final aUpside = _upsideOf(a.item, a.analyst);
    final bUpside = _upsideOf(b.item, b.analyst);
    if (aUpside == null && bUpside == null) return 0;
    if (aUpside == null) return 1;
    if (bUpside == null) return -1;
    return bUpside.compareTo(aUpside);
  });
  return buys;
});

const _predefinedPrompts = [
  'Summarise my portfolio performance and highlight the best and worst performers.',
  'Identify any concentration risks or sectors where I am overexposed.',
  'Which positions have the highest unrealised losses and what are my options?',
  'Evaluate my dividend income and suggest how I could improve yield.',
  'Give me an overall health check of my portfolio with actionable suggestions.',
];

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submit(String query) async {
    if (query.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    await ref.read(analysisProvider.notifier).analyse(query.trim());
    if (mounted) _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analysisState = ref.watch(analysisProvider);
    final apiKeyAsync = ref.watch(activeApiKeyProvider);

    final bool hasKey =
        apiKeyAsync.whenOrNull(data: (k) => k != null && k.isNotEmpty) ?? false;
    final bool isBusy = analysisState.status == AnalysisStatus.loading ||
        analysisState.status == AnalysisStatus.streaming;

    // Auto-scroll as text streams in.
    ref.listen(analysisProvider, (_, next) {
      if (next.status == AnalysisStatus.streaming) _scrollToBottom();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Portfolio Analysis'),
        actions: [
          if (analysisState.status != AnalysisStatus.idle)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset',
              onPressed: isBusy
                  ? null
                  : () {
                      ref.read(analysisProvider.notifier).reset();
                      _controller.clear();
                    },
            ),
          IconButton(
            icon: const Icon(Icons.key_outlined),
            tooltip: 'API Key & Model',
            onPressed: () => context.push('/settings/ai-analysis/key'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                _PrivacyCard(theme: theme),
                const SizedBox(height: 16),
                if (!hasKey) ...[
                  _NoKeyCard(theme: theme),
                ] else ...[
                  if (analysisState.status == AnalysisStatus.idle) ...[
                    const _TopBuysSection(),
                    _PromptsSection(
                      onSelected: (p) {
                        _controller.text = p;
                        _submit(p);
                      },
                    ),
                  ],
                  if (analysisState.status == AnalysisStatus.loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  if (analysisState.status == AnalysisStatus.streaming ||
                      analysisState.status == AnalysisStatus.done) ...[
                    _ResponseCard(
                      text: analysisState.responseText,
                      streaming:
                          analysisState.status == AnalysisStatus.streaming,
                      theme: theme,
                    ),
                    if (analysisState.status == AnalysisStatus.done &&
                        analysisState.suggestions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _SuggestionsSection(
                        suggestions: analysisState.suggestions,
                        theme: theme,
                      ),
                    ],
                  ],
                  if (analysisState.status == AnalysisStatus.error)
                    _ErrorCard(
                        message: analysisState.error ?? 'Unknown error',
                        theme: theme),
                ],
              ],
            ),
          ),
          if (hasKey)
            _InputBar(
              controller: _controller,
              enabled: !isBusy,
              onSubmit: _submit,
            ),
        ],
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: theme.colorScheme.secondaryContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.privacy_tip_outlined,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Your portfolio data is sent to the selected AI provider to generate the analysis. '
                'No data is stored by StockManager — see the Privacy Policy for details.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoKeyCard extends StatelessWidget {
  const _NoKeyCard({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.key_off_outlined,
                    color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Text(
                  'No API Key configured',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Add your API key in Settings → AI Analysis to enable this feature.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => context.push('/settings/ai-analysis/key'),
              child: const Text('Add API Key'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBuysSection extends ConsumerWidget {
  const _TopBuysSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buys = ref.watch(_topBuysProvider);
    if (buys.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Buy recommendations in your portfolio',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          child: Column(
            children: [
              for (int i = 0; i < buys.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _BuyTile(item: buys[i].item, analyst: buys[i].analyst),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _BuyTile extends StatelessWidget {
  const _BuyTile({required this.item, required this.analyst});

  final StockSummaryItem item;
  final AnalystData analyst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStrongBuy =
        analyst.recommendationKey?.toLowerCase() == 'strong_buy';
    final recColor =
        isStrongBuy ? Colors.green.shade800 : Colors.green.shade600;
    final recLabel = isStrongBuy ? 'Strong Buy' : 'Buy';

    String? upsideStr;
    if (item.hasPrice &&
        item.currentPrice.isPositive &&
        analyst.targetMeanPrice.isPositive) {
      final upside =
          analyst.targetMeanPrice.percentChangeFrom(item.currentPrice);
      final sign = upside.isNegative ? '' : '+';
      upsideStr = '$sign${upside.toStringFixed(1)}% to target';
    }

    final subtitleParts = [
      item.stock.symbol,
      if (analyst.numberOfAnalysts != null)
        '${analyst.numberOfAnalysts} analysts',
      if (upsideStr != null) upsideStr,
    ];

    return ListTile(
      dense: true,
      onTap: () => context.push('/stocks/${item.stock.id}'),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.stock.name,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: recColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: recColor.withValues(alpha: 0.35), width: 0.5),
            ),
            child: Text(
              recLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: recColor,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        subtitleParts.join(' · '),
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _PromptsSection extends StatelessWidget {
  const _PromptsSection({required this.onSelected});
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick analysis',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _predefinedPrompts
              .map((p) => ActionChip(
                    label: Text(
                      p.length > 50 ? '${p.substring(0, 50)}…' : p,
                      style: theme.textTheme.bodySmall,
                    ),
                    onPressed: () => onSelected(p),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        Text(
          'Or type a custom question below.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ResponseCard extends StatelessWidget {
  const _ResponseCard({
    required this.text,
    required this.streaming,
    required this.theme,
  });

  final String text;
  final bool streaming;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'AI Analysis',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                if (streaming) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            MarkdownBody(
              data: text,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodyMedium,
                h1: theme.textTheme.titleLarge
                    ?.copyWith(color: theme.colorScheme.onSurface),
                h2: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.onSurface),
                h3: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.onSurface),
                blockquoteDecoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                        color: theme.colorScheme.primary, width: 3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionsSection extends StatelessWidget {
  const _SuggestionsSection({
    required this.suggestions,
    required this.theme,
  });

  final List<StockSuggestion> suggestions;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_circle_outline,
                    size: 16,
                    color: theme.colorScheme.onTertiaryContainer),
                const SizedBox(width: 6),
                Text(
                  'Suggested stocks to add',
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final s in suggestions) ...[
              _SuggestionTile(suggestion: s, theme: theme),
              if (s != suggestions.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.suggestion, required this.theme});

  final StockSuggestion suggestion;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                suggestion.name,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                suggestion.isin,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 2),
              Text(
                suggestion.reason,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.tertiary,
            foregroundColor: theme.colorScheme.onTertiary,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () =>
              context.push('/stocks/add', extra: suggestion.isin),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.theme});
  final String message;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline,
                color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: enabled ? onSubmit : null,
                decoration: const InputDecoration(
                  hintText: 'Ask about your portfolio…',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed: enabled ? () => onSubmit(controller.text) : null,
            ),
          ],
        ),
      ),
    );
  }
}
