import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/log_service.dart';
import '../../core/utils/app_version.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          Icon(Icons.show_chart,
              size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'StockManager',
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Version $appVersion (build $appBuildNumber)',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.balance),
            title: const Text('Licence'),
            subtitle: const Text('GNU General Public License v3.0'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'StockManager',
              applicationVersion: 'v$appVersion',
              applicationLegalese: _legalese,
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Share debug log'),
            subtitle: const Text('Send log file for troubleshooting'),
            trailing: const Icon(Icons.share),
            onTap: () async {
              final logService = ref.read(logServiceProvider);
              final path = logService.filePath;
              if (path.isEmpty) { return; }
              await Share.shareXFiles(
                [XFile(path)],
                subject: 'StockManager debug log',
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Clear debug log'),
            onTap: () async {
              await ref.read(logServiceProvider).clear();
              if (!context.mounted) { return; }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Debug log cleared')),
              );
            },
          ),
        ],
      ),
    );
  }
}

const _legalese =
    'Copyright © 2025 StockManager contributors.\n\n'
    'This program is free software: you can redistribute it and/or modify '
    'it under the terms of the GNU General Public License as published by '
    'the Free Software Foundation, either version 3 of the License, or '
    '(at your option) any later version.\n\n'
    'This program is distributed in the hope that it will be useful, '
    'but WITHOUT ANY WARRANTY; without even the implied warranty of '
    'MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the '
    'GNU General Public License for more details.\n\n'
    'You should have received a copy of the GNU General Public License '
    'along with this program. If not, see https://www.gnu.org/licenses/.';
