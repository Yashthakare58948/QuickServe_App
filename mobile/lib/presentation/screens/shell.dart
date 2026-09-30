import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/enums.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';

class _Tab {
  const _Tab(this.icon, this.activeIcon, this.path, this.label);

  final IconData icon;
  final IconData activeIcon;
  final String path;
  final String label;
}

const _customerTabs = [
  _Tab(Icons.home_outlined, Icons.home, '/home', 'Home'),
  _Tab(Icons.grid_view_outlined, Icons.grid_view, '/services', 'Services'),
  _Tab(Icons.list_alt, Icons.list_alt, '/requests', 'My Requests'),
  _Tab(Icons.person_outline, Icons.person, '/profile', 'Profile'),
];

const _agentTabs = [
  _Tab(Icons.work_outline, Icons.work, '/home', 'Assigned'),
  _Tab(Icons.list_alt, Icons.list_alt, '/requests', 'History'),
  _Tab(Icons.person_outline, Icons.person, '/profile', 'Profile'),
];

const _adminTabs = [
  _Tab(Icons.dashboard_outlined, Icons.dashboard, '/home', 'Home'),
  _Tab(Icons.list_alt, Icons.list_alt, '/requests', 'Requests'),
  _Tab(Icons.person_outline, Icons.person, '/profile', 'Profile'),
];

/// Bottom-navigation shell. Tabs differ by role.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final role = ref.watch(userRoleProvider);

    final tabs = switch (role) {
      UserRole.agent => _agentTabs,
      UserRole.admin => _adminTabs,
      _ => _customerTabs,
    };

    var activeIndex = tabs.indexWhere((t) => location.startsWith(t.path));
    if (activeIndex < 0) activeIndex = 0;

    ref.listen(connectivityProvider, (previous, next) {
      final results = next.value;
      if (results == null) return;
      final online = results.any((r) => r != ConnectivityResult.none);
      if (!online && context.mounted) {
        showErrorSnack(context, 'You appear to be offline. Some actions may fail.');
      }
    });
    ref.watch(connectivityProvider);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: activeIndex,
        onDestinationSelected: (i) => context.go(tabs[i].path),
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.activeIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

/// Emits connectivity changes; used for the offline banner above.
final connectivityProvider =
    StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});
