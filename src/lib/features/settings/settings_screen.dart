import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_settings.dart';
import '../../core/models/chart_range.dart';
import '../../core/utils/app_version.dart';
import 'settings_provider.dart';
import 'widgets/settings_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) => ListView(
          children: [
            SettingsSection(
              title: 'Display',
              children: [
                ListTile(
                  title: const Text('Preferred currency'),
                  subtitle: Text(settings.preferredCurrency),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/currency'),
                ),
                ListTile(
                  title: const Text('Theme'),
                  subtitle: Text(settings.theme.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showThemePicker(context, ref, settings),
                ),
                ListTile(
                  title: const Text('Sparkline period'),
                  subtitle: Text(settings.sparklineRange.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      _showSparklineRangePicker(context, ref, settings),
                ),
              ],
            ),
            SettingsSection(
              title: 'Portfolio',
              children: [
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('Brokers'),
                  subtitle: const Text('Manage your broker accounts'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/brokers'),
                ),
              ],
            ),
            SettingsSection(
              title: 'Market Data',
              children: [
                ListTile(
                  title: const Text('Data Provider'),
                  subtitle: Text(settings.marketDataProvider == MarketDataProvider.finnhub
                      ? 'Finnhub'
                      : 'Yahoo Finance (default)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/market-data'),
                ),
              ],
            ),
            SettingsSection(
              title: 'AI',
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('AI Portfolio Analysis'),
                  subtitle: const Text('Claude-powered portfolio insights'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/ai-analysis'),
                ),
              ],
            ),
            SettingsSection(
              title: 'Synchronisation',
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('Import from Broker'),
                  subtitle: const Text('Import transactions from a broker export'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/broker-import'),
                ),
                ListTile(
                  title: const Text('Local Backup'),
                  subtitle: const Text('Export or import a local ZIP backup'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/backup'),
                ),
                ListTile(
                  title: const Text('Nextcloud Sync'),
                  subtitle: settings.nextcloudUrl != null
                      ? Text(settings.nextcloudUrl!)
                      : const Text('Not configured'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/nextcloud'),
                ),
              ],
            ),
            SettingsSection(
              title: 'Notifications',
              children: [
                SwitchListTile(
                  title: const Text('Enable notifications'),
                  value: settings.notificationsEnabled,
                  onChanged: (v) async {
                    final actions = ref.read(settingsActionsProvider);
                    await actions
                        .saveSettings(settings.copyWith(notificationsEnabled: v));
                  },
                ),
                ListTile(
                  title: const Text('Notification preferences'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/notifications'),
                ),
              ],
            ),
            SettingsSection(
              title: 'About',
              children: [
                ListTile(
                  title: const Text('StockManager'),
                  subtitle: Text(ref
                      .watch(packageInfoProvider)
                      .whenOrNull(data: (i) => 'v${i.version}') ??
                      ''),
                  leading: const Icon(Icons.info_outline),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/about'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showThemePicker(
      BuildContext context, WidgetRef ref, AppSettings settings) async {
    final theme = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          for (final t in ['system', 'light', 'dark'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Text(t[0].toUpperCase() + t.substring(1)),
            ),
        ],
      ),
    );
    if (theme != null) {
      final actions = ref.read(settingsActionsProvider);
      await actions.saveSettings(settings.copyWith(
        theme: switch (theme) {
          'light' => AppTheme.light,
          'dark' => AppTheme.dark,
          _ => AppTheme.system,
        },
      ));
    }
  }

  Future<void> _showSparklineRangePicker(
      BuildContext context, WidgetRef ref, AppSettings settings) async {
    final picked = await showDialog<ChartRange>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Sparkline period'),
        children: [
          for (final r in ChartRange.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(r.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (r == settings.sparklineRange)
                    const Icon(Icons.check, size: 16),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await ref
          .read(settingsActionsProvider)
          .saveSettings(settings.copyWith(sparklineRange: picked));
    }
  }
}
