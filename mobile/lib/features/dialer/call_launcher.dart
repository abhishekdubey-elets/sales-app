import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/common.dart';
import '../auth/data/auth_repository.dart';
import '../auth/providers/auth_controller.dart';
import '../calls/data/call_models.dart';
import '../calls/data/calls_repository.dart';

/// Starts a call to a lead or number.
///
/// * **Provider configured (bridge):** the backend asks the telephony provider to ring the salesperson's
///   calling number and connect the lead. The live call screen opens only when the provider accepted it.
/// * **No provider (device):** the call is logged against the salesperson and the phone's own dialer opens
///   with the number; the salesperson reports how it went when they come back to the app.
Future<void> launchCall(
  BuildContext context,
  WidgetRef ref, {
  String? leadId,
  String? phoneNumber,
  String? displayName,
}) async {
  assert(leadId != null || phoneNumber != null);
  final TelephonyStatus status;
  try {
    status = await ref.read(callsRepositoryProvider).telephonyStatus();
  } catch (e) {
    if (context.mounted) await _showProblem(context, title: 'Couldn\'t start the call', message: errorMessage(e));
    return;
  }
  if (!context.mounted) return;
  if (status.callMode == 'device') {
    await _launchDeviceCall(context, ref, leadId: leadId, phoneNumber: phoneNumber, displayName: displayName);
    return;
  }

  // Bridge calls ring the salesperson's own phone first, so we need that number.
  final user = ref.read(currentUserProvider);
  if (user != null && (user.callingNumber == null || user.callingNumber!.isEmpty)) {
    final saved = await _askCallingNumber(context, ref);
    if (!saved || !context.mounted) return;
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
    if (context.mounted) await _showCallError(context, e);
  }
}

Future<void> _launchDeviceCall(
  BuildContext context,
  WidgetRef ref, {
  String? leadId,
  String? phoneNumber,
  String? displayName,
}) async {
  try {
    final start = await runWithProgress(
      context,
      () => ref.read(callsRepositoryProvider).startDevice(leadId: leadId, phoneNumber: phoneNumber),
      message: 'Preparing call to ${displayName ?? phoneNumber ?? 'lead'}…',
    );
    if (!context.mounted) return;
    ref.invalidate(recentCallsProvider);
    context.push('/call/device/${start.call.id}', extra: start);
  } catch (e) {
    if (context.mounted) await _showCallError(context, e);
  }
}

Future<void> _showCallError(BuildContext context, Object e) {
  final code = e is ApiException ? e.code : null;
  return _showProblem(
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

/// Asks for the salesperson's calling number right here (instead of sending them to Profile) and saves it.
Future<bool> _askCallingNumber(BuildContext context, WidgetRef ref) async {
  final saved = await showDialog<bool>(context: context, builder: (_) => const _CallingNumberDialog());
  return saved ?? false;
}

class _CallingNumberDialog extends ConsumerStatefulWidget {
  const _CallingNumberDialog();

  @override
  ConsumerState<_CallingNumberDialog> createState() => _CallingNumberDialogState();
}

class _CallingNumberDialogState extends ConsumerState<_CallingNumberDialog> {
  final _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _error = 'Enter your 10-digit mobile number');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = await ref.read(authRepositoryProvider).updateMe(callingNumber: value);
      ref.read(authControllerProvider.notifier).setUser(user);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.phone_iphone),
      title: const Text('Your calling number'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('The call rings this phone first, then connects the lead. You only need to enter it once.'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_saving,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Mobile number',
              hintText: '98765 43210',
              prefixIcon: const Icon(Icons.call_outlined),
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save and call'),
        ),
      ],
    );
  }
}

Future<void> _showProblem(BuildContext context, {required String title, required String message}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(Icons.phone_disabled, color: Theme.of(dialogContext).colorScheme.error),
      title: Text(title),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close'))],
    ),
  );
}
