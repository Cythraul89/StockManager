import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum BrokerImportStatus { available, comingSoon }

class BrokerImportOption {
  const BrokerImportOption({
    required this.id,
    required this.name,
    required this.subtitle,
    this.status = BrokerImportStatus.comingSoon,
  });

  final String id;
  final String name;
  final String subtitle;
  final BrokerImportStatus status;
}

const _brokers = [
  BrokerImportOption(
    id: 'flatex',
    name: 'Flatex',
    subtitle: 'CSV orders export',
    status: BrokerImportStatus.available,
  ),
  BrokerImportOption(
    id: 'degiro',
    name: 'DEGIRO',
    subtitle: 'CSV transactions export',
  ),
  BrokerImportOption(
    id: 'interactive_brokers',
    name: 'Interactive Brokers',
    subtitle: 'Flex Query / Activity Statement',
  ),
  BrokerImportOption(
    id: 'trade_republic',
    name: 'Trade Republic',
    subtitle: 'CSV export',
  ),
  BrokerImportOption(
    id: 'scalable_capital',
    name: 'Scalable Capital',
    subtitle: 'CSV transactions export',
  ),
  BrokerImportOption(
    id: 'comdirect',
    name: 'Comdirect',
    subtitle: 'CSV account / depot export',
  ),
];

class BrokerImportScreen extends StatelessWidget {
  const BrokerImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Import from Broker')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Select your broker to import existing transactions, '
                      'positions, and dividends directly from an exported file.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final broker in _brokers)
            _BrokerTile(broker: broker),
        ],
      ),
    );
  }
}

class _BrokerTile extends StatelessWidget {
  const _BrokerTile({required this.broker});

  final BrokerImportOption broker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = broker.status == BrokerImportStatus.available;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: available
          ? theme.colorScheme.surfaceContainerLow
          : theme.colorScheme.surfaceContainerLowest,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _BrokerAvatar(name: broker.name, available: available),
        title: Text(
          broker.name,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: available
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        subtitle: Text(
          broker.subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant
                .withValues(alpha: available ? 1.0 : 0.5),
          ),
        ),
        trailing: available
            ? FilledButton(
                onPressed: () => _onImport(context, broker),
                child: const Text('Import'),
              )
            : _ComingSoonChip(theme: theme),
        onTap: available ? () => _onImport(context, broker) : null,
      ),
    );
  }

  void _onImport(BuildContext context, BrokerImportOption broker) {
    context.push('/settings/broker-import/${broker.id}');
  }
}

class _BrokerAvatar extends StatelessWidget {
  const _BrokerAvatar({required this.name, required this.available});

  final String name;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 20,
      backgroundColor: available
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Text(
        name[0].toUpperCase(),
        style: theme.textTheme.titleSmall?.copyWith(
          color: available
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurface.withValues(alpha: 0.4),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ComingSoonChip extends StatelessWidget {
  const _ComingSoonChip({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        'Coming soon',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
