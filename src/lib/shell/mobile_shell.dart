import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MobileShell extends StatelessWidget {
  const MobileShell({super.key, required this.child});

  final Widget child;

  static const _tabs = [
    _TabItem(label: 'Dashboard', icon: Icons.dashboard_outlined, path: '/'),
    _TabItem(label: 'Stocks', icon: Icons.show_chart, path: '/stocks'),
    _TabItem(label: 'Dividends', icon: Icons.payments_outlined, path: '/dividends'),
    _TabItem(label: 'Brokers', icon: Icons.account_balance_outlined, path: '/brokers'),
    _TabItem(label: 'Settings', icon: Icons.settings_outlined, path: '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _indexForPath(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) => context.go(_tabs[i].path),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              label: tab.label,
            ),
        ],
      ),
    );
  }

  static int _indexForPath(String path) {
    for (var i = _tabs.length - 1; i >= 0; i--) {
      if (path.startsWith(_tabs[i].path) &&
          (_tabs[i].path == '/' ? path == '/' : true)) {
        return i;
      }
    }
    return 0;
  }
}

class _TabItem {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.path,
  });

  final String label;
  final IconData icon;
  final String path;
}
