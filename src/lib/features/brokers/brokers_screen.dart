import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../stocks/stocks_provider.dart';
import 'widgets/broker_tile.dart';

class BrokersScreen extends ConsumerWidget {
  const BrokersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brokersAsync = ref.watch(brokersStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Brokers')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/brokers/add'),
        tooltip: 'Add broker',
        child: const Icon(Icons.add),
      ),
      body: brokersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (brokers) {
          if (brokers.isEmpty) {
            return const Center(
              child: Text('No brokers yet.\nTap + to add one.',
                  textAlign: TextAlign.center),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: brokers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => BrokerTile(broker: brokers[i]),
          );
        },
      ),
    );
  }
}
