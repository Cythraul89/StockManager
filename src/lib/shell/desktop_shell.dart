import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DesktopShell extends StatelessWidget {
  const DesktopShell({super.key, required this.child});

  final Widget child;

  static const _navItems = [
    _NavItem(label: 'Dashboard', icon: Icons.dashboard_outlined, path: '/'),
    _NavItem(label: 'Stocks', icon: Icons.show_chart, path: '/stocks'),
    _NavItem(label: 'Dividends', icon: Icons.payments_outlined, path: '/dividends'),
    _NavItem(label: 'Brokers', icon: Icons.account_balance_outlined, path: '/brokers'),
    _NavItem(label: 'Settings', icon: Icons.settings_outlined, path: '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _indexForPath(location);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1200,
              selectedIndex: currentIndex,
              onDestinationSelected: (i) => context.go(_navItems[i].path),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Stock\nManager',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              destinations: [
                for (final item in _navItems)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    label: Text(item.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  static int _indexForPath(String path) {
    for (var i = _navItems.length - 1; i >= 0; i--) {
      if (path.startsWith(_navItems[i].path) &&
          (_navItems[i].path == '/' ? path == '/' : true)) {
        return i;
      }
    }
    return 0;
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.path,
  });

  final String label;
  final IconData icon;
  final String path;
}
