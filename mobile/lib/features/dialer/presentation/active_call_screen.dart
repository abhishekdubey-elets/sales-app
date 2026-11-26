import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/realtime_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/providers/auth_controller.dart';
import '../../calls/data/call_models.dart';
import '../../calls/data/calls_repository.dart';
import '../../settings/data/settings_repository.dart';
import 'disposition_sheet.dart';

/// Live call screen. Status changes come from the provider via backend
/// webhooks → WebSocket `call.status`; `/calls/{id}` is polled every 3s as a fallback.
class ActiveCallScreen extends ConsumerStatefulWidget {
  const ActiveCallScreen({super.key, required this.callId, this.initial});

  final String callId;
  final HumanCall? initial;

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen> {
  HumanCall? _call;
  Object? _error;
  Timer? _poll;
  Timer? _tick;
  StreamSubscription<RealtimeEvent>? _events;
  bool _hangingUp = false;
  bool _dispositionShown = false;
  bool _callMode = false; // true when the backend reports in-app VoIP mode

  @override
  void initState() {
    super.initState();
    _call = widget.initial;
    _events = ref.read(realtimeServiceProvider).events.listen(_onEvent);
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _call?.status == CallStatus.connected) setState(() {});
    });
    _refresh();
    _loadCallMode();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _events?.cancel();
    super.dispose();
  }

  Future<void> _loadCallMode() async {
    final role = ref.read(currentUserProvider)?.role;
    if (role != UserRole.admin) return; // telephony-status is admin-only; others assume bridge mode
    try {
      final status = await ref.read(settingsRepositoryProvider).telephonyStatus();
      if (mounted) setState(() => _callMode = status.isVoip);
    } catch (_) {}
  }

  void _onEvent(RealtimeEvent event) {
    if (event.type != RealtimeEvent.callStatus && event.type != RealtimeEvent.callIncoming) return;
    if (event.data['id']?.toString() != widget.callId) return;
    _apply(HumanCall.fromJson(event.data));
  }

  Future<void> _refresh() async {
    try {
      final call = await ref.read(callsRepositoryProvider).get(widget.callId);
      _apply(call);
    } catch (e) {
      if (mounted && _call == null) setState(() => _error = e);
    }
  }

  void _apply(HumanCall call) {
    if (!mounted) return;
    setState(() {
      _call = call;
      _error = null;
    });
    if (call.status.isTerminal) {
      _poll?.cancel();
      _tick?.cancel();
      _maybeShowDisposition(call);
    }
  }

  Future<void> _maybeShowDisposition(HumanCall call) async {
    if (_dispositionShown || call.outcome != null) return;
    _dispositionShown = true;
    // Let the final status render before the sheet slides up.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    final updated = await showDispositionSheet(context, call);
    if (!mounted) return;
    if (updated != null) {
      setState(() => _call = updated);
      showSnack(context, 'Call outcome saved');
    }
  }

  Future<void> _hangup() async {
    final ok = await showConfirmDialog(
      context,
      title: 'End call?',
      message: 'This asks the telephony provider to disconnect the call.',
      confirmLabel: 'End call',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _hangingUp = true);
    try {
      final call = await ref.read(callsRepositoryProvider).hangup(widget.callId);
      _apply(call);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _hangingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    if (call == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null
            ? ErrorState(error: _error!, onRetry: _refresh)
            : const LoadingView(message: 'Loading call…'),
      );
    }
    final theme = Theme.of(context);
    final active = call.status.isActive;
    final elapsed = call.answeredAt == null
        ? Duration.zero
        : (call.endedAt ?? DateTime.now()).difference(call.answeredAt!);
    final statusColor = callStatusColor(call.status);
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: () => context.pop()),
          title: Text(call.direction == CallDirection.inbound ? 'Inbound call' : 'Outbound call'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Spacer(),
                    _PulsingAvatar(name: call.displayName, active: active, color: statusColor),
                    const SizedBox(height: 20),
                    Text(call.displayName, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                    if (call.phoneNumber != null && call.leadName != null)
                      Text(
                        call.phoneNumber!,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    const SizedBox(height: 16),
                    StatusChip.callStatus(call.status),
                    const SizedBox(height: 12),
                    Text(
                      call.answeredAt != null ? formatTimer(elapsed) : _waitingText(call.status),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    if (call.failureReason != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        call.failureReason!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const Spacer(),
                    if (active && !_callMode) const _BridgeModeNotice(),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CallControl(
                          icon: Icons.mic_off_outlined,
                          label: 'Mute',
                          enabled: false,
                          tooltip: _callMode
                              ? 'In-app audio controls need the provider Voice SDK (not configured)'
                              : 'Bridge mode: use your phone\'s call screen to mute',
                        ),
                        _CallControl(
                          icon: Icons.volume_up_outlined,
                          label: 'Speaker',
                          enabled: false,
                          tooltip: _callMode
                              ? 'In-app audio controls need the provider Voice SDK (not configured)'
                              : 'Bridge mode: use your phone\'s call screen for speaker',
                        ),
                        _CallControl(
                          icon: Icons.edit_note,
                          label: 'Outcome',
                          enabled: call.status.isTerminal,
                          tooltip: 'Log outcome',
                          onTap: () async {
                            final updated = await showDispositionSheet(context, call);
                            if (updated != null && mounted) setState(() => _call = updated);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (active)
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: FloatingActionButton(
                          heroTag: 'hangup',
                          backgroundColor: AppColors.danger,
                          foregroundColor: Colors.white,
                          shape: const CircleBorder(),
                          onPressed: _hangingUp ? null : _hangup,
                          tooltip: 'End call',
                          child: _hangingUp
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Icon(Icons.call_end, size: 32),
                        ),
                      )
                    else
                      FilledButton.icon(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.check),
                        label: Text(call.outcome != null ? 'Done · ${call.outcome!.label}' : 'Close'),
                      ),
                    const SizedBox(height: 12),
                    if (call.provider != null)
                      Text(
                        'via ${call.provider} · ref ${call.providerCallId ?? '—'}',
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _waitingText(CallStatus s) => switch (s) {
    CallStatus.initiated => 'Calling your phone…',
    CallStatus.ringing => 'Ringing…',
    CallStatus.connected => 'Connected',
    _ => s.label,
  };
}

class _BridgeModeNotice extends StatelessWidget {
  const _BridgeModeNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Bridge call: your phone rings first, then the lead is connected. '
              'Mute and speaker are on your phone\'s own call screen.',
            ),
          ),
        ],
      ),
    );
  }
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Column(
        children: [
          IconButton.filledTonal(
            iconSize: 26,
            padding: const EdgeInsets.all(16),
            onPressed: enabled ? onTap : null,
            icon: Icon(icon),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: enabled ? null : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingAvatar extends StatefulWidget {
  const _PulsingAvatar({required this.name, required this.active, required this.color});

  final String name;
  final bool active;
  final Color color;

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _PulsingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) _controller.repeat();
    if (!widget.active) _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Stack(
          alignment: Alignment.center,
          children: [
            if (widget.active)
              Container(
                width: 96 + 44 * _controller.value,
                height: 96 + 44 * _controller.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.25 * (1 - _controller.value)),
                ),
              ),
            child!,
          ],
        ),
        child: AppAvatar(name: widget.name, radius: 48),
      ),
    );
  }
}
