import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/dividend.dart';
import '../../core/models/exchange_rate.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_helpers.dart';
import '../settings/settings_provider.dart';
import '../stocks/stocks_provider.dart';
import 'dividends_provider.dart';
import 'widgets/confirm_dividend_dialog.dart';
import 'widgets/dividend_income_chart.dart';
import 'widgets/dividend_tile.dart';

class DividendsScreen extends ConsumerStatefulWidget {
  const DividendsScreen({super.key});

  @override
  ConsumerState<DividendsScreen> createState() => _DividendsScreenState();
}

class _DividendsScreenState extends ConsumerState<DividendsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dividendsAsync = ref.watch(allDividendsProvider);
    final rates = ref.watch(exchangeRatesProvider).value ?? [];
    final preferred =
        ref.watch(settingsStreamProvider).value?.preferredCurrency ?? 'USD';
    final estimate = ref.watch(estimatedAnnualDividendProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dividends'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Received'),
            Tab(text: 'Upcoming'),
          ],
        ),
      ),
      body: dividendsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (dividends) {
          final pending = dividends
              .where((d) => d.isPendingConfirmation)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          final paid = dividends
              .where((d) =>
                  d.type == DividendType.paid && !d.isPendingConfirmation)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          final upcoming = dividends
              .where((d) =>
                  d.type == DividendType.expected &&
                  DateHelpers.daysUntil(d.date) >= 0)
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));

          return TabBarView(
            controller: _tabController,
            children: [
              _buildReceivedTab(dividends, paid, pending, rates, preferred, estimate),
              _buildUpcomingTab(upcoming, rates, preferred),
            ],
          );
        },
      ),
    );
  }

  // ── Received tab ─────────────────────────────────────────────────────────────

  Widget _buildReceivedTab(
    List<Dividend> allDividends,
    List<Dividend> paid,
    List<Dividend> pending,
    List<ExchangeRate> rates,
    String preferred,
    DividendEstimate? estimate,
  ) {
    // Group paid by year (most-recent first).
    final yearGroups = <int, List<Dividend>>{};
    for (final d in paid) {
      (yearGroups[d.date.year] ??= []).add(d);
    }
    final years = yearGroups.keys.toList()..sort((a, b) => b.compareTo(a));

    // Compute totals in preferred currency (skip dividends with no rate).
    var allTimeTotal = Decimal.zero;
    final yearTotals = <int, Decimal>{};
    for (final d in paid) {
      final amount = _toPreferred(d.netAmount, d.currency, preferred, rates);
      if (amount == null) continue;
      allTimeTotal += amount;
      yearTotals[d.date.year] =
          (yearTotals[d.date.year] ?? Decimal.zero) + amount;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DividendIncomeChart(dividends: allDividends),
        const SizedBox(height: 16),
        if (pending.isNotEmpty) ...[
          Text(
            'Pending confirmation',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.orange),
          ),
          const SizedBox(height: 4),
          Text(
            'Review auto-fetched dividends to include them in calculations.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: pending
                  .map((d) => DividendTile(
                        dividend: d,
                        onTap: () => context.push(
                            '/stocks/${d.stockId}/dividends/${d.id}/edit'),
                        onConfirm: () => _confirmDividend(d),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (paid.isNotEmpty) ...[
          _buildTotalsSummary(allTimeTotal, yearTotals, preferred),
          const SizedBox(height: 16),
        ],
        if (estimate != null) ...[
          _buildEstimateCard(estimate),
          const SizedBox(height: 16),
        ],
        if (paid.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('No paid dividends recorded yet.')),
          )
        else
          for (final year in years) ...[
            _buildSectionHeader(
              year.toString(),
              yearTotals[year] != null
                  ? CurrencyFormatter.format(yearTotals[year]!, preferred)
                  : null,
            ),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: yearGroups[year]!
                    .map((d) => DividendTile(
                          dividend: d,
                          onTap: () => context.push(
                              '/stocks/${d.stockId}/dividends/${d.id}/edit'),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
      ],
    );
  }

  Widget _buildTotalsSummary(
    Decimal allTime,
    Map<int, Decimal> yearTotals,
    String preferred,
  ) {
    final sortedYears = yearTotals.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryRow(
              'Total all-time',
              CurrencyFormatter.format(allTime, preferred),
              bold: true,
            ),
            const Divider(height: 16),
            for (final year in sortedYears)
              _summaryRow(
                'Total $year',
                CurrencyFormatter.format(yearTotals[year]!, preferred),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstimateCard(DividendEstimate estimate) {
    final theme = Theme.of(context);
    final partial = estimate.coveredStocks < estimate.totalStocks;
    final coverage = '${estimate.coveredStocks}/${estimate.totalStocks} stocks';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryRow(
              'Est. annual income',
              '~${CurrencyFormatter.format(estimate.total, estimate.currency)}',
              bold: true,
            ),
            const SizedBox(height: 6),
            Text(
              partial
                  ? 'Based on 5Y avg yield · $coverage with analyst data loaded'
                  : 'Based on 5Y avg yield · all $coverage',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  // ── Upcoming tab ─────────────────────────────────────────────────────────────

  Widget _buildUpcomingTab(
    List<Dividend> upcoming,
    List<ExchangeRate> rates,
    String preferred,
  ) {
    if (upcoming.isEmpty) {
      return const Center(child: Text('No upcoming dividends.'));
    }

    // Group by "YYYY-MM" key (already sorted ascending).
    final monthGroups = <String, List<Dividend>>{};
    for (final d in upcoming) {
      final key =
          '${d.date.year}-${d.date.month.toString().padLeft(2, '0')}';
      (monthGroups[key] ??= []).add(d);
    }
    final months = monthGroups.keys.toList()..sort();

    // Grand total — only where totalAmount is set and convertible.
    var grandTotal = Decimal.zero;
    var hasGrandTotal = false;
    for (final d in upcoming) {
      if (d.totalAmount == null) continue;
      final amount = _toPreferred(d.totalAmount!, d.currency, preferred, rates);
      if (amount == null) continue;
      grandTotal += amount;
      hasGrandTotal = true;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (hasGrandTotal) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _summaryRow(
                'Total expected',
                '~${CurrencyFormatter.format(grandTotal, preferred)}',
                bold: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        for (final month in months) ...[
          _buildMonthHeader(month, monthGroups[month]!, rates, preferred),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: monthGroups[month]!
                  .map((d) => DividendTile(
                        dividend: d,
                        onTap: () => context.push(
                            '/stocks/${d.stockId}/dividends/${d.id}/edit'),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildMonthHeader(
    String monthKey,
    List<Dividend> items,
    List<ExchangeRate> rates,
    String preferred,
  ) {
    final parts = monthKey.split('-');
    final label = DateFormat('MMMM yyyy')
        .format(DateTime(int.parse(parts[0]), int.parse(parts[1])));

    var monthTotal = Decimal.zero;
    var hasTotal = false;
    for (final d in items) {
      if (d.totalAmount == null) continue;
      final amount = _toPreferred(d.totalAmount!, d.currency, preferred, rates);
      if (amount == null) continue;
      monthTotal += amount;
      hasTotal = true;
    }

    return _buildSectionHeader(
      label,
      hasTotal ? '~${CurrencyFormatter.format(monthTotal, preferred)}' : null,
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String label, String? trailing) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Row(
      children: [
        Text(label, style: style),
        if (trailing != null) ...[
          const Spacer(),
          Text(
            trailing,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    final theme = Theme.of(context);
    final style = bold
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }

  Decimal? _toPreferred(
    Decimal amount,
    String currency,
    String preferred,
    List<ExchangeRate> rates,
  ) {
    if (currency == preferred) return amount;
    final rate = ExchangeRate.find(rates, currency, preferred);
    if (rate == null) return null;
    return rate.convert(amount);
  }

  Future<void> _confirmDividend(Dividend dividend) async {
    final confirmed = await showDialog<Dividend>(
      context: context,
      builder: (_) => ConfirmDividendDialog(dividend: dividend),
    );
    if (confirmed == null || !mounted) return;
    try {
      await ref.read(stockActionsProvider).confirmDividend(confirmed);
    } catch (e) {
      debugPrint('DividendsScreen: confirmDividend failed: $e');
    }
  }
}
