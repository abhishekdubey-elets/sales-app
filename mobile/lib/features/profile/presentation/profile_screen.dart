import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/realtime_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/providers/auth_controller.dart';
import '../../leads/presentation/lead_form_screen.dart' show validatePhone;

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _editField(
    BuildContext context,
    WidgetRef ref, {
    required String field,
    required String title,
    String? value,
  }) async {
    final result = await showTextInputDialog(
      context,
      title: title,
      initialValue: value,
      keyboardType: TextInputType.phone,
      validator: (v) => validatePhone(v, required: false),
    );
    if (result == null || !context.mounted) return;
    try {
      final repo = ref.read(authRepositoryProvider);
      final user = field == 'phone' ? await repo.updateMe(phone: result) : await repo.updateMe(callingNumber: result);
      ref.read(authControllerProvider.notifier).setUser(user);
      if (context.mounted) showSnack(context, '$title updated');
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final connection = ref.watch(realtimeConnectionProvider).value;
    final role = user.role;

    Widget tile(IconData icon, String title, VoidCallback onTap, {String? subtitle}) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ContentConstraint(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        AppAvatar(name: user.fullName, radius: 30),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user.fullName, style: theme.textTheme.titleLarge),
                              Text(user.email, style: theme.textTheme.bodyMedium),
                              const SizedBox(height: 4),
                              Text(
                                '${role.label}${user.teamName != null ? ' · ${user.teamName}' : ''}',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.phone_outlined),
                        title: const Text('Phone'),
                        subtitle: Text(user.phone ?? 'Not set'),
                        trailing: const Icon(Icons.edit_outlined, size: 20),
                        onTap: () => _editField(context, ref, field: 'phone', title: 'Phone', value: user.phone),
                      ),
                      ListTile(
                        leading: const Icon(Icons.ring_volume_outlined),
                        title: const Text('Calling number'),
                        subtitle: Text(user.callingNumber ?? 'Not set — only needed for calls through a telephony provider'),
                        trailing: const Icon(Icons.edit_outlined, size: 20),
                        onTap: () => _editField(
                          context,
                          ref,
                          field: 'calling_number',
                          title: 'Calling number',
                          value: user.callingNumber,
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionHeader(title: 'My work'),
                Card(
                  child: Column(
                    children: [
                      tile(Icons.insights_outlined, 'My performance', () => context.push('/performance')),
                      tile(Icons.history, 'Call history', () => context.push('/calls')),
                      tile(Icons.event_note_outlined, 'Follow-ups', () => context.push('/followups')),
                      tile(Icons.notifications_none, 'Notifications', () => context.push('/notifications')),
                    ],
                  ),
                ),
                if (role.isManagerOrAdmin) ...[
                  const SectionHeader(title: 'Management'),
                  Card(
                    child: Column(
                      children: [
                        tile(
                          Icons.groups_outlined,
                          role.isAdmin ? 'Team management' : 'My team',
                          () => context.push('/team'),
                        ),
                        tile(Icons.bar_chart, 'Analytics & exports', () => context.push('/analytics')),
                        tile(Icons.campaign_outlined, 'AI campaigns', () => context.go('/ai?tab=campaigns')),
                        if (role.isAdmin) ...[
                          tile(
                            Icons.settings_outlined,
                            'Organisation settings',
                            () => context.push('/settings'),
                            subtitle: 'Calling hours, recording, consent, credits',
                          ),
                          tile(Icons.policy_outlined, 'Audit log', () => context.push('/audit-logs')),
                        ],
                      ],
                    ),
                  ),
                ],
                const SectionHeader(title: 'Security'),
                Card(
                  child: Column(
                    children: [
                      tile(Icons.devices_outlined, 'Active sessions', () => context.go('/profile/sessions')),
                      tile(Icons.lock_reset, 'Change password', () => context.go('/profile/password')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () async {
                    final ok = await showConfirmDialog(
                      context,
                      title: 'Sign out?',
                      message: 'You will need to sign in again to make calls.',
                      confirmLabel: 'Sign out',
                    );
                    if (ok) await ref.read(authControllerProvider.notifier).logout();
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Server ${Env.apiBaseUrl} · live updates ${switch (connection) {
                    RealtimeConnection.connected => 'connected',
                    RealtimeConnection.connecting => 'connecting…',
                    _ => 'offline',
                  }}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
