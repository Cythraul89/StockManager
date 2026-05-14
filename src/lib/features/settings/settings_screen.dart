import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_settings.dart';
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
              ],
            ),
            SettingsSection(
              title: 'Synchronisation',
              children: [
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
                  subtitle: Text('v$appVersion'),
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
      builder: (_) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          for (final t in ['system', 'light', 'dark'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, t),
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
}
