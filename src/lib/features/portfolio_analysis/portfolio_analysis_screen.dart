import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/dashboard_provider.dart';
import '../dashboard/widgets/portfolio_history_chart.dart';

class PortfolioAnalysisScreen extends ConsumerWidget {
  const PortfolioAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(portfolioHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Analysis')),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (points) {
          if (points.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No data yet.\nAdd transactions to see your portfolio history.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PortfolioHistoryChart(points: points),
            ],
          );
        },
      ),
    );
  }
}
