import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/calls/data/call_models.dart';
import '../network/realtime_service.dart';
import '../theme/app_theme.dart';

/// Bottom navigation (phones) / navigation rail (wide screens) around the five tabs.
/// Also surfaces inbound calls pushed over the WebSocket.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    (icon: Icons.space_dashboard_outlined, selected: Icons.space_dashboard, label: 'Dashboard'),
    (icon: Icons.people_alt_outlined, selected: Icons.people_alt, label: 'Leads'),
    (icon: Icons.dialpad_outlined, selected: Icons.dialpad, label: 'Dialer'),
    (icon: Icons.smart_toy_outlined, selected: Icons.smart_toy, label: 'AI Agents'),
    (icon: Icons.person_outline, selected: Icons.person, label: 'Profile'),
  ];

  void _onSelect(int index) => navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      final event = next.value;
      if (event == null || event.type != RealtimeEvent.callIncoming) return;
      _showIncoming(context, HumanCall.fromJson(event.data));
    });

    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _onSelect,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: CircleAvatar(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  child: const Text('E', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: Text(d.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onSelect,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: d.label),
        ],
      ),
    );
  }

  void _showIncoming(BuildContext context, HumanCall call) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.phone_callback, color: AppColors.success, size: 36),
        title: Text('Incoming call from ${call.displayName}'),
        content: Text(
          'The call is ringing on your registered phone. '
          'Answer it there; this screen tracks its status and lets you log the outcome.',
        ),
        actions: [
          if (call.leadId != null)
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.go('/leads/${call.leadId}');
              },
              child: const Text('Open lead'),
            ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.push('/call/${call.id}', extra: call);
            },
            child: const Text('Track call'),
          ),
        ],
      ),
    );
  }
}
