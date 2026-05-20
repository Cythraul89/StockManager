import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    final secondary = body?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          Text('Last updated: 2026-05-18', style: secondary),
          const SizedBox(height: 20),
          _Section(
            title: 'Summary',
            child: Text(
              'StockManager stores all portfolio data locally on your device. '
              'No data is uploaded to any server operated by this application '
              'or its developers.',
              style: body,
            ),
          ),
          _Section(
            title: 'Data stored on your device',
            child: Text(
              'All portfolio data (brokers, stocks, transactions, dividends, '
              'settings) is stored in a local SQLite database on your device. '
              'It never leaves your device unless you explicitly trigger a '
              'Nextcloud sync or an AI analysis request.',
              style: body,
            ),
          ),
          _Section(
            title: 'Data sent to third-party services',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'When an internet connection is available, the app contacts '
                  'the following external services:',
                  style: body,
                ),
                const SizedBox(height: 12),
                _ServiceTable(theme: theme),
                const SizedBox(height: 8),
                Text(
                  'No names, email addresses, passwords, device identifiers, '
                  'or personally identifying information are transmitted to any '
                  'of the services above.',
                  style: secondary,
                ),
              ],
            ),
          ),
          _Section(
            title: 'Nextcloud synchronisation',
            child: Text(
              'If you configure Nextcloud sync, the app uploads a backup file '
              '(ODS spreadsheet containing your portfolio data) to your own '
              'Nextcloud server using credentials you provide. This data goes '
              'directly to your server; it is not routed through or visible to '
              'the developers of StockManager.',
              style: body,
            ),
          ),
          _Section(
            title: 'Analytics and tracking',
            child: Text(
              'StockManager contains no analytics, crash-reporting, advertising, '
              'or user-tracking SDKs. The developers receive no telemetry of '
              'any kind.',
              style: body,
            ),
          ),
          _Section(
            title: 'Data retention and deletion',
            child: Text(
              'All data is stored on your device. Uninstalling the app removes '
              'all locally stored data. Any backups you have uploaded to your '
              'Nextcloud instance must be deleted there separately.',
              style: body,
            ),
          ),
          _Section(
            title: 'Contact',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'For questions about this privacy policy, please open an issue at:',
                  style: body,
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => launchUrl(
                    Uri.parse(
                        'https://github.com/Cythraul89/StockManager/issues'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(
                    'github.com/Cythraul89/StockManager/issues',
                    style: body?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _ServiceTable extends StatelessWidget {
  const _ServiceTable({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    const services = [
      (
        'Yahoo Finance',
        'Ticker symbol',
        'Live prices, chart data',
        'Automatically, when app is open',
      ),
      (
        'OpenFIGI',
        'ISIN',
        'Resolve ticker, name, exchange',
        'When adding or researching a stock',
      ),
      (
        'Open Exchange Rates',
        'None',
        'Currency exchange rates',
        'Automatically, when app is open',
      ),
      (
        'Finnhub',
        'Ticker symbol',
        'Analyst ratings & price targets',
        'When viewing analysis (if API key configured)',
      ),
      (
        'Anthropic',
        'Portfolio data',
        'AI portfolio analysis',
        'Only when you explicitly request analysis',
      ),
    ];

    final headerStyle = theme.textTheme.labelSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final cellStyle = theme.textTheme.bodySmall;
    const border = BorderSide(color: Color(0x22808080));

    TableRow headerRow(List<String> cells) => TableRow(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          children: cells
              .map((c) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    child: Text(c, style: headerStyle),
                  ))
              .toList(),
        );

    TableRow dataRow(
            String service, String data, String purpose, String when) =>
        TableRow(children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(service, style: cellStyle),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(data, style: cellStyle),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(purpose, style: cellStyle),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(when, style: cellStyle),
          ),
        ]);

    return Table(
      border: TableBorder.all(color: const Color(0x22808080)),
      columnWidths: const {
        0: FlexColumnWidth(1.4),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(1.6),
        3: FlexColumnWidth(1.8),
      },
      children: [
        headerRow(['Service', 'Data sent', 'Purpose', 'When']),
        for (final s in services) dataRow(s.$1, s.$2, s.$3, s.$4),
      ],
    );
  }
}
