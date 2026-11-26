import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../calls/data/call_models.dart';
import '../../calls/data/calls_repository.dart';

/// After a call: outcome, notes, follow-up, lead status → POST /calls/{id}/disposition.
/// Returns the updated call, or null if dismissed.
Future<HumanCall?> showDispositionSheet(BuildContext context, HumanCall call) {
  return showModalBottomSheet<HumanCall>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DispositionSheet(call: call),
  );
}

class _DispositionSheet extends ConsumerStatefulWidget {
  const _DispositionSheet({required this.call});

  final HumanCall call;

  @override
  ConsumerState<_DispositionSheet> createState() => _DispositionSheetState();
}

class _DispositionSheetState extends ConsumerState<_DispositionSheet> {
  CallOutcome? _outcome;
  LeadStatus? _leadStatus;
  DateTime? _followupAt;
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Unanswered calls default to "No response" so logging is one tap.
    if (widget.call.status != CallStatus.completed && widget.call.status != CallStatus.connected) {
      _setOutcome(CallOutcome.noResponse);
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _setOutcome(CallOutcome o) {
    _outcome = o;
    if (widget.call.leadId != null) _leadStatus = o.suggestedLeadStatus;
  }

  Future<void> _pickFollowup() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _followupAt ?? now.add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_followupAt ?? DateTime(now.year, now.month, now.day, 11)),
    );
    if (time == null) return;
    setState(() => _followupAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final outcome = _outcome;
    if (outcome == null) {
      setState(() => _error = 'Select an outcome');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(callsRepositoryProvider)
          .disposition(
            widget.call.id,
            outcome: outcome.value,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            followupAt: _followupAt,
            leadStatus: _leadStatus?.value,
          );
      ref.invalidate(recentCallsProvider);
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final call = widget.call;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Log call outcome', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${call.displayName} · ${call.status.label}'
              '${call.talkSeconds > 0 ? ' · ${formatDuration(call.talkSeconds)}' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text('Outcome *', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in CallOutcome.values)
                  ChoiceChip(
                    label: Text(o.label),
                    selected: _outcome == o,
                    selectedColor: outcomeColor(o).withValues(alpha: 0.18),
                    onSelected: (_) => setState(() => _setOutcome(o)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Call notes', hintText: 'What was discussed?'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_outlined),
              title: Text(_followupAt == null ? 'Schedule follow-up' : formatDateTime(_followupAt)),
              subtitle: _outcome?.suggestsFollowup == true && _followupAt == null
                  ? const Text('Recommended for this outcome')
                  : null,
              trailing: _followupAt == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _followupAt = null)),
              onTap: _pickFollowup,
            ),
            if (call.leadId != null) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<LeadStatus>(
                key: ValueKey(_leadStatus),
                initialValue: _leadStatus,
                decoration: const InputDecoration(labelText: 'Update lead status'),
                items: [for (final s in LeadStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                onChanged: (v) => setState(() => _leadStatus = v),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save outcome'),
            ),
          ],
        ),
      ),
    );
  }
}
