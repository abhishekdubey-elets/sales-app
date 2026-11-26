import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_back_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_chip.dart';
import '../../calls/data/call_models.dart';
import '../../campaigns/data/campaign_models.dart';
import '../data/settings_models.dart';
import '../data/settings_repository.dart';

/// Admin: organisation-wide calling and compliance settings.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), title: const Text('Organisation settings')),
      body: AsyncValueView<OrgSettings>(
        value: ref.watch(orgSettingsProvider),
        onRetry: () => ref.invalidate(orgSettingsProvider),
        data: (s) => _SettingsForm(initial: s),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.initial});

  final OrgSettings initial;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final _timezone = TextEditingController(text: widget.initial.timezone);
  late final _aiDisclosure = TextEditingController(text: widget.initial.aiDisclosureText);
  late final _recordingDisclosure = TextEditingController(text: widget.initial.recordingDisclosureText);
  late final _credits = TextEditingController(text: '${widget.initial.callingCreditsMinutes}');
  late final _lowCredit = TextEditingController(text: '${widget.initial.lowCreditThresholdMinutes}');
  late String _start = widget.initial.callingHoursStart;
  late String _end = widget.initial.callingHoursEnd;
  late String _summaryTime = widget.initial.dailySummaryTime;
  late final Set<int> _days = {...widget.initial.callingDays};
  late bool _recording = widget.initial.recordingEnabled;
  late bool _consent = widget.initial.requireConsentForAiCalls;
  late bool _mask = widget.initial.maskNumbersForExecutives;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_timezone, _aiDisclosure, _recordingDisclosure, _credits, _lowCredit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _time(String current) async {
    final parts = current.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 9, minute: int.tryParse(parts.last) ?? 0),
    );
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final settings = OrgSettings(
        timezone: _timezone.text.trim().isEmpty ? 'Asia/Kolkata' : _timezone.text.trim(),
        callingHoursStart: _start,
        callingHoursEnd: _end,
        callingDays: _days.toList()..sort(),
        recordingEnabled: _recording,
        recordingDisclosureText: _recordingDisclosure.text.trim(),
        aiDisclosureText: _aiDisclosure.text.trim(),
        requireConsentForAiCalls: _consent,
        maskNumbersForExecutives: _mask,
        callingCreditsMinutes: int.tryParse(_credits.text) ?? 0,
        lowCreditThresholdMinutes: int.tryParse(_lowCredit.text) ?? 0,
        dailySummaryTime: _summaryTime,
      );
      await ref.read(settingsRepositoryProvider).update(settings.toJson());
      ref.invalidate(orgSettingsProvider);
      if (mounted) showSnack(context, 'Settings saved');
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.initial;
    final remaining = s.callingCreditsMinutes - s.creditsUsedMinutes;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ContentConstraint(
          maxWidth: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TelephonyCard(),
              const SizedBox(height: 12),
              InfoCard(
                title: 'Permitted calling hours',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Human and AI calls are blocked outside these hours. Confirm them against current TRAI / '
                      'telecom rules for your use case.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final t = await _time(_start);
                              if (t != null) setState(() => _start = t);
                            },
                            child: Text('From $_start'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final t = await _time(_end);
                              if (t != null) setState(() => _end = t);
                            },
                            child: Text('Until $_end'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in CampaignSchedule.dayLabels.entries)
                          FilterChip(
                            label: Text(e.value),
                            selected: _days.contains(e.key),
                            onSelected: (v) => setState(() => v ? _days.add(e.key) : _days.remove(e.key)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _timezone,
                      decoration: const InputDecoration(labelText: 'Organisation timezone'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InfoCard(
                title: 'Disclosure & consent',
                child: Column(
                  children: [
                    TextField(
                      controller: _aiDisclosure,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'AI disclosure (spoken first on every AI call)',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Require consent for AI calls'),
                      subtitle: const Text('Only leads with consent “granted” are dialled by AI agents'),
                      value: _consent,
                      onChanged: (v) => setState(() => _consent = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Call recording'),
                      subtitle: const Text('Enable only where lawful; the notice below is played first'),
                      value: _recording,
                      onChanged: (v) => setState(() => _recording = v),
                    ),
                    TextField(
                      controller: _recordingDisclosure,
                      enabled: _recording,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Recording notice', alignLabelWithHint: true),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mask phone numbers for executives'),
                      subtitle: const Text('Calls are placed server-side, so executives never need the full number'),
                      value: _mask,
                      onChanged: (v) => setState(() => _mask = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InfoCard(
                title: 'Calling credits',
                trailing: StatusChip(
                  label: '$remaining min left',
                  color: remaining <= s.lowCreditThresholdMinutes ? AppColors.danger : AppColors.success,
                ),
                child: Column(
                  children: [
                    KeyValueRow(label: 'Used', value: '${s.creditsUsedMinutes} min'),
                    TextField(
                      controller: _credits,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Credit budget (minutes)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _lowCredit,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Low-credit alert threshold (minutes)'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InfoCard(
                title: 'Notifications',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: const Text('Daily performance summary'),
                  subtitle: Text('Sent at $_summaryTime'),
                  onTap: () async {
                    final t = await _time(_summaryTime);
                    if (t != null) setState(() => _summaryTime = t);
                  },
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save settings'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TelephonyCard extends ConsumerWidget {
  const _TelephonyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InfoCard(
      title: 'Telephony provider',
      child: AsyncValueView<TelephonyStatus>(
        value: ref.watch(telephonyStatusProvider),
        compactError: true,
        onRetry: () => ref.invalidate(telephonyStatusProvider),
        loading: const SizedBox(height: 60, child: LoadingView()),
        data: (t) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(t.provider ?? 'None', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 8),
                StatusChip(
                  label: t.configured ? 'Configured' : 'Not configured',
                  color: t.configured ? AppColors.success : AppColors.danger,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                StatusChip(label: 'Mode: ${t.callMode}', color: AppColors.primary, dense: true),
                _cap('AI media streaming', t.supportsAiStreaming),
                _cap('Recording', t.supportsRecording),
                _cap('Inbound', t.supportsInbound),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Provider credentials live only in the server environment and are never sent to the app.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cap(String label, bool ok) => StatusChip(
    label: label,
    color: ok ? AppColors.success : AppColors.neutral,
    icon: ok ? Icons.check : Icons.close,
    dense: true,
  );
}
