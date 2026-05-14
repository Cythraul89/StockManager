import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_settings.dart';
import 'settings_provider.dart';
import 'widgets/settings_section.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notification preferences')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) => ListView(
          children: [
            SettingsSection(
              title: 'Price alerts',
              children: [
                ListTile(
                  title: const Text('Alert threshold'),
                  subtitle: Text(
                      '${settings.priceAlertThresholdPct.toStringAsFixed(1)}% price change'),
                  trailing: const Icon(Icons.edit),
                  onTap: () => _editThreshold(context, ref, settings),
                ),
              ],
            ),
            SettingsSection(
              title: 'Dividend alerts',
              children: [
                ListTile(
                  title: const Text('Lead time'),
                  subtitle: Text(
                      '${settings.dividendAlertDays} day(s) before payment'),
                  trailing: const Icon(Icons.edit),
                  onTap: () => _editDividendDays(context, ref, settings),
                ),
              ],
            ),
            // FCM push section — Android only
            if (Platform.isAndroid)
              const SettingsSection(
                title: 'Push notifications (Android)',
                children: [
                  ListTile(
                    title: Text('Background price alerts'),
                    subtitle: Text(
                        'Uses WorkManager to check prices in the background '
                        '(approximately every 15 minutes).'),
                    isThreeLine: true,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editThreshold(
      BuildContext context, WidgetRef ref, AppSettings settings) async {
    final ctrl = TextEditingController(
        text: settings.priceAlertThresholdPct.toStringAsFixed(1));
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Price alert threshold'),
        content: TextField(
          controller: ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Percentage (%)', suffixText: '%'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != null) {
      try {
        final pct = Decimal.parse(result.trim());
        await ref
            .read(settingsActionsProvider)
            .saveSettings(settings.copyWith(priceAlertThresholdPct: pct));
      } catch (e) {
        debugPrint('NotificationSettings: invalid threshold value: $e');
      }
    }
  }

  Future<void> _editDividendDays(
      BuildContext context, WidgetRef ref, AppSettings settings) async {
    final ctrl = TextEditingController(
        text: settings.dividendAlertDays.toString());
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Dividend alert lead time'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(labelText: 'Days before payment'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != null) {
      final days = int.tryParse(result.trim());
      if (days != null && days >= 0) {
        await ref
            .read(settingsActionsProvider)
            .saveSettings(settings.copyWith(dividendAlertDays: days));
      }
    }
  }
}
