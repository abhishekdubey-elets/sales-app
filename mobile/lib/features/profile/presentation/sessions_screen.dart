import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/data/auth_repository.dart';

final _sessionsProvider = FutureProvider.autoDispose<List<UserSession>>(
  (ref) => ref.watch(authRepositoryProvider).sessions(),
);

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Active sessions')),
      body: AsyncValueView<List<UserSession>>(
        value: ref.watch(_sessionsProvider),
        onRetry: () => ref.invalidate(_sessionsProvider),
        data: (sessions) => sessions.isEmpty
            ? const EmptyState(title: 'No sessions')
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(_sessionsProvider),
                child: ContentConstraint(
                  maxWidth: 640,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final s in sessions)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: const Icon(Icons.devices_outlined),
                            title: Row(
                              children: [
                                Flexible(child: Text(s.deviceName ?? 'Unknown device')),
                                if (s.current) ...[
                                  const SizedBox(width: 8),
                                  const StatusChip(label: 'This device', color: AppColors.success, dense: true),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              'Signed in ${formatDateTime(s.createdAt)} · last used ${formatRelative(s.lastUsedAt)}',
                            ),
                            trailing: s.current
                                ? null
                                : TextButton(
                                    onPressed: () async {
                                      final ok = await showConfirmDialog(
                                        context,
                                        title: 'Sign out this device?',
                                        message: '${s.deviceName ?? 'The device'} will need to sign in again.',
                                        confirmLabel: 'Sign out',
                                        destructive: true,
                                      );
                                      if (!ok) return;
                                      try {
                                        await ref.read(authRepositoryProvider).revokeSession(s.id);
                                        ref.invalidate(_sessionsProvider);
                                      } catch (e) {
                                        if (context.mounted) showSnack(context, errorMessage(e), error: true);
                                      }
                                    },
                                    child: const Text('Revoke'),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
