import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
          Icon(Icons.show_chart, size: 72, color: theme.colorScheme.primary),
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
          const SizedBox(height: 24),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'StockManager is a personal portfolio tracker provided for '
                'informational purposes only. Nothing in this app constitutes '
                'financial advice or a recommendation to buy or sell any security.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
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
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/about/privacy-policy'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Source code'),
            subtitle: const Text('GitHub — GPL-3.0'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _launch('https://github.com/Cythraul89/StockManager'),
          ),
          const Divider(),
          const _SectionHeader('Data sources'),
          const ListTile(
            dense: true,
            leading: Icon(Icons.currency_exchange, size: 20),
            title: Text('Exchange rates'),
            subtitle: Text('Powered by Open Exchange Rates'),
          ),
          const ListTile(
            dense: true,
            leading: Icon(Icons.search, size: 20),
            title: Text('Security identifiers'),
            subtitle: Text(
              'Powered by OpenFIGI. FIGI® is a registered trademark of '
              'Bloomberg Finance L.P.',
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
              if (path.isEmpty) return;
              await SharePlus.instance.share(
                ShareParams(
                  files: [XFile(path)],
                  subject: 'StockManager debug log',
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Clear debug log'),
            onTap: () async {
              await ref.read(logServiceProvider).clear();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Debug log cleared')),
              );
            },
          ),
        ],
      ),
    );
  }

  static Future<void> _launch(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelMedium
            ?.copyWith(color: theme.colorScheme.primary),
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
