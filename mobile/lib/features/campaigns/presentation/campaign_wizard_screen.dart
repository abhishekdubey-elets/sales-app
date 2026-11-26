import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/file_pick.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../ai_agents/data/ai_models.dart';
import '../../ai_agents/data/ai_repository.dart';
import '../data/campaign_models.dart';
import '../data/campaigns_repository.dart';

/// Details + agent → leads → schedule & retries → review & launch.
/// The draft is created when leaving step 1 so leads can be attached to it.
class CampaignWizardScreen extends ConsumerStatefulWidget {
  const CampaignWizardScreen({super.key});

  @override
  ConsumerState<CampaignWizardScreen> createState() => _CampaignWizardScreenState();
}

class _CampaignWizardScreenState extends ConsumerState<CampaignWizardScreen> {
  int _step = 0;
  bool _busy = false;
  Campaign? _draft;

  // Step 1
  final _detailsKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  AIAgent? _agent;

  // Step 2
  LeadStatus? _filterStatus;
  final _filterSource = TextEditingController();
  final _filterIndustry = TextEditingController();
  String? _leadsMessage;

  // Step 3
  CampaignSchedule _schedule = const CampaignSchedule();
  int _maxAttempts = 3;
  final _retryDelay = TextEditingController(text: '60');
  int _concurrency = 2;
  int _perMinute = 4;

  @override
  void dispose() {
    for (final c in [_name, _description, _filterSource, _filterIndustry, _retryDelay]) {
      c.dispose();
    }
    super.dispose();
  }

  CampaignDraft _draftBody() => CampaignDraft(
    name: _name.text.trim(),
    description: _description.text.trim().isEmpty ? null : _description.text.trim(),
    agentId: _agent!.id,
    schedule: _schedule,
    maxAttempts: _maxAttempts,
    retryDelayMinutes: int.tryParse(_retryDelay.text) ?? 60,
    maxConcurrentCalls: _concurrency,
    callsPerMinute: _perMinute,
  );

  Future<bool> _guard(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      return true;
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshDraft() async {
    final id = _draft?.id;
    if (id == null) return;
    final c = await ref.read(campaignsRepositoryProvider).get(id);
    if (mounted) setState(() => _draft = c);
  }

  Future<void> _next() async {
    switch (_step) {
      case 0:
        if (!(_detailsKey.currentState?.validate() ?? false)) return;
        if (_agent == null) {
          showSnack(context, 'Select an AI agent', error: true);
          return;
        }
        final ok = await _guard(() async {
          final repo = ref.read(campaignsRepositoryProvider);
          final body = _draftBody();
          final c = _draft == null ? await repo.create(body) : await repo.update(_draft!.id, body.toJson());
          setState(() => _draft = c);
        });
        if (ok) setState(() => _step = 1);
      case 1:
        if ((_draft?.stats.totalLeads ?? 0) == 0) {
          final proceed = await showConfirmDialog(
            context,
            title: 'No leads added',
            message: 'The campaign has no leads yet. You can add them later, but it can\'t start without any.',
            confirmLabel: 'Continue anyway',
          );
          if (!proceed) return;
        }
        setState(() => _step = 2);
      case 2:
        if (_schedule.daysOfWeek.isEmpty) {
          showSnack(context, 'Pick at least one calling day', error: true);
          return;
        }
        final ok = await _guard(() async {
          final c = await ref.read(campaignsRepositoryProvider).update(_draft!.id, _draftBody().toJson());
          setState(() => _draft = c);
        });
        if (ok) setState(() => _step = 3);
    }
  }

  Future<void> _addByFilter() async {
    await _guard(() async {
      final result = await ref.read(campaignsRepositoryProvider).addLeadsByFilter(_draft!.id, {
        'status': _filterStatus?.value,
        'source': _filterSource.text.trim(),
        'industry': _filterIndustry.text.trim(),
      });
      setState(
        () => _leadsMessage =
            'Added ${result.added} lead(s), skipped ${result.skipped} (already added, '
            'opted out or not eligible).',
      );
      await _refreshDraft();
    });
  }

  Future<void> _upload() async {
    final file = await pickSpreadsheet();
    if (file == null) return;
    await _guard(() async {
      final r = await ref.read(campaignsRepositoryProvider).importLeads(_draft!.id, file.bytes, file.name);
      setState(
        () => _leadsMessage =
            '${file.name}: ${r.totalRows} rows · ${r.created} new leads · '
            '${r.duplicates} existing leads matched · ${r.errors.length} errors.',
      );
      await _refreshDraft();
    });
  }

  Future<void> _finish({required bool launch}) async {
    final id = _draft!.id;
    if (launch) {
      final ok = await showConfirmDialog(
        context,
        title: 'Launch campaign?',
        message:
            'The AI agent will start calling ${_draft!.stats.totalLeads} lead(s) during the scheduled hours. '
            'Every call opens with the AI disclosure, and opted-out numbers are skipped.',
        confirmLabel: 'Launch',
      );
      if (!ok) return;
      final done = await _guard(() async {
        await ref.read(campaignsRepositoryProvider).control(id, 'start');
      });
      if (!done) return;
    }
    ref.invalidate(campaignsProvider);
    if (mounted) context.pushReplacement('/ai/campaigns/$id');
  }

  Future<void> _pickTime(bool start) async {
    final parts = (start ? _schedule.startTime : _schedule.endTime).split(':');
    final initial = TimeOfDay(hour: int.tryParse(parts.first) ?? 10, minute: int.tryParse(parts.last) ?? 0);
    final t = await showTimePicker(context: context, initialTime: initial);
    if (t == null) return;
    final value = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => _schedule = start ? _schedule.copyWith(startTime: value) : _schedule.copyWith(endTime: value));
  }

  Future<void> _pickDate(bool start) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (d == null) return;
    final value = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    setState(() => _schedule = start ? _schedule.copyWith(startDate: value) : _schedule.copyWith(endDate: value));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New AI campaign')),
      body: ContentConstraint(
        maxWidth: 760,
        child: Stepper(
          currentStep: _step,
          onStepTapped: (i) {
            if (i < _step) setState(() => _step = i);
          },
          controlsBuilder: (context, details) {
            if (_step == 3) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _next,
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Continue'),
                  ),
                  const SizedBox(width: 12),
                  if (_step > 0)
                    TextButton(onPressed: _busy ? null : () => setState(() => _step--), child: const Text('Back')),
                ],
              ),
            );
          },
          steps: [
            Step(
              title: const Text('Details & agent'),
              isActive: _step >= 0,
              state: _step > 0 ? StepState.complete : StepState.indexed,
              content: _detailsStep(),
            ),
            Step(
              title: const Text('Leads'),
              subtitle: _draft != null ? Text('${_draft!.stats.totalLeads} lead(s)') : null,
              isActive: _step >= 1,
              state: _step > 1 ? StepState.complete : StepState.indexed,
              content: _leadsStep(),
            ),
            Step(
              title: const Text('Schedule & retries'),
              isActive: _step >= 2,
              state: _step > 2 ? StepState.complete : StepState.indexed,
              content: _scheduleStep(),
            ),
            Step(title: const Text('Review & launch'), isActive: _step >= 3, content: _reviewStep()),
          ],
        ),
      ),
    );
  }

  Widget _detailsStep() {
    final agents = ref.watch(aiAgentsProvider);
    return Form(
      key: _detailsKey,
      child: Column(
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Campaign name *',
              hintText: 'e.g. eGov Summit sponsor outreach',
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          AsyncValueView<List<AIAgent>>(
            value: agents,
            compactError: true,
            onRetry: () => ref.invalidate(aiAgentsProvider),
            loading: const LinearProgressIndicator(),
            data: (list) {
              final active = list.where((a) => a.isActive).toList();
              if (active.isEmpty) {
                return ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('No active AI agents'),
                  subtitle: const Text('Create an agent first.'),
                  trailing: TextButton(onPressed: () => context.go('/ai/agents/new'), child: const Text('Create')),
                );
              }
              return DropdownButtonFormField<String>(
                initialValue: _agent?.id,
                decoration: const InputDecoration(labelText: 'AI agent *', prefixIcon: Icon(Icons.smart_toy_outlined)),
                items: [
                  for (final a in active)
                    DropdownMenuItem(value: a.id, child: Text('${a.name} · ${a.config.language.label}')),
                ],
                onChanged: (id) => setState(() => _agent = active.firstWhere((a) => a.id == id)),
                validator: (v) => v == null ? 'Select an agent' : null,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _leadsStep() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Add leads from your database by filter, or upload a CSV/Excel file. Duplicates are matched to existing '
          'leads by phone/email; opted-out numbers are never called.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        InfoCard(
          title: 'From existing leads',
          child: Column(
            children: [
              DropdownButtonFormField<LeadStatus?>(
                initialValue: _filterStatus,
                decoration: const InputDecoration(labelText: 'Lead status'),
                items: [
                  const DropdownMenuItem<LeadStatus?>(value: null, child: Text('Any status')),
                  for (final s in LeadStatus.values) DropdownMenuItem<LeadStatus?>(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _filterStatus = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _filterSource,
                decoration: const InputDecoration(labelText: 'Lead source contains'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _filterIndustry,
                decoration: const InputDecoration(labelText: 'Industry'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _busy || _draft == null ? null : _addByFilter,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Add matching leads'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        InfoCard(
          title: 'Upload a list',
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy || _draft == null ? null : _upload,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Upload CSV / Excel'),
            ),
          ),
        ),
        if (_leadsMessage != null) ...[
          const SizedBox(height: 12),
          Text(_leadsMessage!, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.success)),
        ],
        const SizedBox(height: 8),
        Text('Leads in campaign: ${_draft?.stats.totalLeads ?? 0}', style: theme.textTheme.titleSmall),
      ],
    );
  }

  Widget _counter(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 28,
          child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  Widget _scheduleStep() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Calling days', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in CampaignSchedule.dayLabels.entries)
              FilterChip(
                label: Text(e.value),
                selected: _schedule.daysOfWeek.contains(e.key),
                onSelected: (v) => setState(() {
                  final days = {..._schedule.daysOfWeek};
                  v ? days.add(e.key) : days.remove(e.key);
                  _schedule = _schedule.copyWith(daysOfWeek: days.toList()..sort());
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickTime(true),
                icon: const Icon(Icons.schedule),
                label: Text('From ${_schedule.startTime}'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickTime(false),
                icon: const Icon(Icons.schedule),
                label: Text('Until ${_schedule.endTime}'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickDate(true),
                child: Text(_schedule.startDate == null ? 'Start date: now' : 'Starts ${_schedule.startDate}'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickDate(false),
                child: Text(_schedule.endDate == null ? 'No end date' : 'Ends ${_schedule.endDate}'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: _schedule.timezone,
          decoration: const InputDecoration(labelText: 'Timezone (IANA)', helperText: 'Default Asia/Kolkata'),
          onChanged: (v) => _schedule = _schedule.copyWith(timezone: v.trim().isEmpty ? 'Asia/Kolkata' : v.trim()),
        ),
        const SizedBox(height: 8),
        Text(
          'Calls are also limited to the organisation\'s permitted calling hours set by your admin.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const Divider(height: 32),
        _counter('Max attempts per lead', _maxAttempts, 1, 10, (v) => setState(() => _maxAttempts = v)),
        TextField(
          controller: _retryDelay,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Retry delay (minutes)'),
        ),
        const SizedBox(height: 8),
        _counter('Max concurrent calls', _concurrency, 1, 20, (v) => setState(() => _concurrency = v)),
        _counter('Calls per minute', _perMinute, 1, 60, (v) => setState(() => _perMinute = v)),
      ],
    );
  }

  Widget _reviewStep() {
    final d = _draft;
    if (d == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyValueRow(label: 'Name', value: d.name),
        KeyValueRow(label: 'Agent', value: d.agentName ?? _agent?.name),
        KeyValueRow(label: 'Leads', value: '${d.stats.totalLeads}'),
        KeyValueRow(label: 'Days', value: d.schedule.daysLabel),
        KeyValueRow(label: 'Hours', value: '${d.schedule.startTime}–${d.schedule.endTime} (${d.schedule.timezone})'),
        KeyValueRow(label: 'Attempts', value: '${d.maxAttempts}, ${d.retryDelayMinutes} min apart'),
        KeyValueRow(label: 'Throughput', value: '${d.maxConcurrentCalls} concurrent · ${d.callsPerMinute}/min'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.ai.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Compliance: each call starts with the AI disclosure; DND/opt-out and consent checks run before every dial; '
            'a lead is never called by two agents (or an agent and a salesperson) at once.',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => _finish(launch: false),
                child: const Text('Save as draft'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy || d.stats.totalLeads == 0 ? null : () => _finish(launch: true),
                icon: const Icon(Icons.rocket_launch_outlined),
                label: const Text('Launch'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
