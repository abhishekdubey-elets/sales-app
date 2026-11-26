import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../calls/data/call_models.dart';
import '../../calls/data/calls_repository.dart';
import 'disposition_sheet.dart';

/// A call placed from the salesperson's own phone (no telephony provider configured).
///
/// The call is already logged against the salesperson. This screen opens the phone's dialer with the
/// number, measures how long the salesperson was away, and when they come back asks whether the call
/// connected and for how long; then the usual outcome sheet (notes, follow-up, lead status).
class DeviceCallScreen extends ConsumerStatefulWidget {
  const DeviceCallScreen({super.key, required this.start, this.openDialer = _launchDialer});

  final DeviceCallStart start;

  /// Opens the phone's dialer with the number; returns false if it couldn't. Injectable for tests.
  final Future<bool> Function(Uri telUri) openDialer;

  static Future<bool> _launchDialer(Uri telUri) => launchUrl(telUri);

  @override
  ConsumerState<DeviceCallScreen> createState() => _DeviceCallScreenState();
}

class _DeviceCallScreenState extends ConsumerState<DeviceCallScreen> {
  late final AppLifecycleListener _lifecycle;
  final _duration = TextEditingController();
  DateTime? _dialedAt;
  bool _leftApp = false;
  bool _returned = false;
  bool? _connected;
  bool _saving = false;
  bool _done = false;
  String? _error;

  HumanCall get _call => widget.start.call;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _leftApp = _dialedAt != null,
      onPause: () => _leftApp = _dialedAt != null,
      onResume: _onBackInApp,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _openDialer());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _openDialer() async {
    final uri = Uri(scheme: 'tel', path: widget.start.dialNumber);
    var opened = false;
    try {
      opened = await widget.openDialer(uri);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    if (opened) {
      _dialedAt ??= DateTime.now();
    } else {
      setState(() => _error = 'Couldn\'t open the phone dialer. Dial ${widget.start.dialNumber} manually, then log it here.');
      _dialedAt ??= DateTime.now();
      _returned = true;
    }
  }

  void _onBackInApp() {
    if (!_leftApp || _dialedAt == null || _returned) return;
    final away = DateTime.now().difference(_dialedAt!).inSeconds;
    setState(() {
      _returned = true;
      _duration.text = _formatMmSs(away);
    });
  }

  static String _formatMmSs(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  /// Accepts "m:ss", "mm:ss" or plain minutes ("3"). Returns null when invalid.
  static int? _parseDuration(String text) {
    final t = text.trim();
    if (t.isEmpty) return 0;
    final parts = t.split(':');
    if (parts.length == 1) {
      final minutes = double.tryParse(parts[0]);
      return minutes == null || minutes < 0 ? null : (minutes * 60).round();
    }
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]);
      final s = int.tryParse(parts[1]);
      if (m == null || s == null || m < 0 || s < 0 || s > 59) return null;
      return m * 60 + s;
    }
    return null;
  }

  Future<void> _save({bool didNotCall = false}) async {
    final connected = didNotCall ? false : _connected;
    if (connected == null) {
      setState(() => _error = 'Choose whether the call connected.');
      return;
    }
    final seconds = didNotCall ? 0 : _parseDuration(_duration.text);
    if (seconds == null) {
      setState(() => _error = 'Enter the duration as minutes:seconds, e.g. 2:30');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(callsRepositoryProvider)
          .deviceResult(_call.id, connected: connected, durationSeconds: connected ? seconds : 0);
      setState(() => _done = true);
      ref.invalidate(recentCallsProvider);
      if (!mounted) return;
      if (!didNotCall) await showDispositionSheet(context, updated);
      // Navigator.pop (not maybePop) so the "log this call first" guard doesn't fire again.
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log this call first'),
        content: const Text(
          'Tell us whether the call connected so it counts in your call history and reports. '
          'If you didn\'t place it, choose "I didn\'t call".',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('I didn\'t call')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Log it')),
        ],
      ),
    );
    if (leave == true) await _save(didNotCall: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _call.leadName ?? widget.start.dialNumber;
    return PopScope(
      canPop: _done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Phone call')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 8),
                  Center(child: AppAvatar(name: name, radius: 36)),
                  const SizedBox(height: 12),
                  Text(name, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    widget.start.dialNumber,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.sim_card_outlined, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _returned
                                  ? 'Welcome back. Log how the call went below.'
                                  : 'Your phone\'s dialer is open with this number. Place the call from your phone, '
                                        'then come back here to log it.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _openDialer,
                    icon: const Icon(Icons.call),
                    label: const Text('Open dialer again'),
                  ),
                  const SizedBox(height: 24),
                  Text('How did it go?', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, icon: Icon(Icons.call), label: Text('Connected')),
                      ButtonSegment(value: false, icon: Icon(Icons.call_missed), label: Text('Not connected')),
                    ],
                    emptySelectionAllowed: true,
                    selected: {?_connected},
                    onSelectionChanged: _saving
                        ? null
                        : (s) => setState(() {
                            _connected = s.isEmpty ? null : s.first;
                            _error = null;
                          }),
                  ),
                  if (_connected == true) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _duration,
                      enabled: !_saving,
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        labelText: 'Talk time (min:sec)',
                        hintText: '2:30',
                        prefixIcon: const Icon(Icons.timer_outlined),
                        helperText: _returned ? 'Estimated from the time you were in the dialer — adjust if needed' : null,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.success, minimumSize: const Size.fromHeight(48)),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: const Text('Save and add outcome'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _saving ? null : () => _save(didNotCall: true),
                    child: const Text('I didn\'t place this call'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
