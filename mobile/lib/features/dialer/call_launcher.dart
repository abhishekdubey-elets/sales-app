import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/common.dart';
import '../auth/providers/auth_controller.dart';
import '../calls/data/calls_repository.dart';

/// Requests a call through the backend and opens the live call screen only
/// when the telephony provider accepted it (the call has a provider_call_id).
Future<void> launchCall(
  BuildContext context,
  WidgetRef ref, {
  String? leadId,
  String? phoneNumber,
  String? displayName,
}) async {
  assert(leadId != null || phoneNumber != null);
  final user = ref.read(currentUserProvider);
  if (user != null && (user.callingNumber == null || user.callingNumber!.isEmpty)) {
    await _showProblem(
      context,
      title: 'Add your calling number',
      message:
          'Calls are bridged: the provider rings your phone first, then connects the lead. '
          'Add the number you take calls on in Profile > Calling number.',
      actionLabel: 'Open profile',
      onAction: () => context.go('/profile'),
    );
    return;
  }
  try {
    final call = await runWithProgress(
      context,
      () => ref.read(callsRepositoryProvider).start(leadId: leadId, phoneNumber: phoneNumber),
      message: 'Requesting a call to ${displayName ?? phoneNumber ?? 'lead'}…',
    );
    if (!context.mounted) return;
    if (!call.isPlacedByProvider) {
      await _showProblem(
        context,
        title: 'Call not placed',
        message: call.failureReason ?? 'The telephony provider did not confirm the call. No call was placed.',
      );
      return;
    }
    ref.invalidate(recentCallsProvider);
    context.push('/call/${call.id}', extra: call);
  } catch (e) {
    if (!context.mounted) return;
    final code = e is ApiException ? e.code : null;
    await _showProblem(
      context,
      title: switch (code) {
        'telephony_not_configured' => 'Calling not configured',
        'opted_out' => 'Number opted out',
        'outside_calling_hours' => 'Outside calling hours',
        'lead_busy' => 'Lead is on another call',
        _ => 'Couldn\'t place the call',
      },
      message: errorMessage(e),
    );
  }
}

Future<void> _showProblem(
  BuildContext context, {
  required String title,
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(Icons.phone_disabled, color: Theme.of(dialogContext).colorScheme.error),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close')),
        if (actionLabel != null)
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onAction?.call();
            },
            child: Text(actionLabel),
          ),
      ],
    ),
  );
}
