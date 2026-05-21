import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/claude_service.dart';
import '../dashboard/dashboard_provider.dart';
import '../stocks/stocks_provider.dart';

enum AnalysisStatus { idle, loading, streaming, done, error }

class AnalysisState {
  const AnalysisState({
    this.status = AnalysisStatus.idle,
    this.responseText = '',
    this.error,
  });

  final AnalysisStatus status;
  final String responseText;
  final String? error;

  AnalysisState copyWith({
    AnalysisStatus? status,
    String? responseText,
    String? error,
  }) =>
      AnalysisState(
        status: status ?? this.status,
        responseText: responseText ?? this.responseText,
        error: error ?? this.error,
      );
}

final analysisProvider =
    NotifierProvider<AnalysisNotifier, AnalysisState>(AnalysisNotifier.new);

class AnalysisNotifier extends Notifier<AnalysisState> {
  @override
  AnalysisState build() => const AnalysisState();

  void reset() => state = const AnalysisState();

  Future<void> analyse(String userQuery) async {
    state = const AnalysisState(status: AnalysisStatus.loading);

    // Read API key and model directly from DB to avoid stale provider cache.
    final row =
        await ref.read(databaseProvider).settingsDao.getSettings();
    final apiKey = row?.claudeApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      state = const AnalysisState(
        status: AnalysisStatus.error,
        error: 'No Claude API key configured. Add your key in Settings → AI Analysis.',
      );
      return;
    }

    PortfolioSummary summary;
    try {
      summary = await ref.read(portfolioSummaryProvider.future);
    } catch (e) {
      state = AnalysisState(
        status: AnalysisStatus.error,
        error: 'Could not load portfolio data: $e',
      );
      return;
    }

    final model = row?.claudeModel ?? defaultClaudeModel;
    final portfolioJson = _serialisePortfolio(summary);
    final systemPrompt = _buildSystemPrompt();
    final userMessage = _buildUserMessage(portfolioJson, userQuery);

    state = const AnalysisState(
        status: AnalysisStatus.streaming, responseText: '');

    try {
      await for (final chunk in ref
          .read(claudeServiceProvider)
          .streamAnalysis(
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            userMessage: userMessage,
          )) {
        state = state.copyWith(
          responseText: state.responseText + chunk,
        );
      }
      state = state.copyWith(status: AnalysisStatus.done);
    } on ClaudeApiException catch (e) {
      state = AnalysisState(
        status: AnalysisStatus.error,
        error: e.message,
      );
    } catch (e) {
      state = AnalysisState(
        status: AnalysisStatus.error,
        error: 'Unexpected error: $e',
      );
    }
  }

  String _buildSystemPrompt() =>
      'You are an expert financial analyst helping a private investor understand their stock portfolio. '
      'You provide clear, balanced, and actionable insights. You are not a licensed financial advisor '
      'and always remind the user that your analysis is for informational purposes only and does not '
      'constitute investment advice. You present both opportunities and risks objectively.';

  String _buildUserMessage(String portfolioJson, String query) =>
      'Here is my current portfolio data (all monetary values are in the currency field shown):\n\n'
      '```json\n$portfolioJson\n```\n\n'
      '$query';

  String _serialisePortfolio(PortfolioSummary summary) {
    final items = summary.stockItems.map((item) {
      return {
        'ticker': item.stock.symbol,
        'name': item.stock.name,
        'broker': item.broker?.name ?? 'Unknown',
        'currency': item.stock.currency,
        'shares_held': item.sharesHeld.toString(),
        'avg_buy_price': item.avgBuyPrice.toString(),
        'current_price': item.currentPrice.toString(),
        'current_value_preferred': item.currentValue.toString(),
        'unrealised_pnl_preferred': item.unrealisedPnl.toString(),
        'unrealised_pnl_pct': '${item.unrealisedPnlPct.toString()}%',
        'annual_yield_pct': '${item.annualYieldPct.toString()}%',
        'has_live_price': item.hasPrice,
      };
    }).toList();

    final portfolio = {
      'preferred_currency': summary.currency,
      'total_value': summary.totalValue.toString(),
      'total_invested': summary.totalInvested.toString(),
      'unrealised_pnl': summary.unrealisedPnl.toString(),
      'unrealised_pnl_pct': '${summary.unrealisedPnlPct.toString()}%',
      'realised_pnl': summary.realisedPnl.toString(),
      'all_time_dividends': summary.allTimeDividends.toString(),
      'current_year_dividends': summary.currentYearDividends.toString(),
      'positions': items,
    };

    // Simple hand-rolled JSON so we don't need dart:convert encoder quirks.
    return _encodeJson(portfolio);
  }

  String _encodeJson(Object? value) {
    if (value == null) return 'null';
    if (value is bool) return value.toString();
    if (value is num) return value.toString();
    if (value is String) {
      return '"${value.replaceAll('"', '\\"')}"';
    }
    if (value is List) {
      return '[${value.map(_encodeJson).join(', ')}]';
    }
    if (value is Map) {
      final pairs = value.entries
          .map((e) => '${_encodeJson(e.key.toString())}: ${_encodeJson(e.value)}')
          .join(',\n  ');
      return '{\n  $pairs\n}';
    }
    return '"$value"';
  }
}
