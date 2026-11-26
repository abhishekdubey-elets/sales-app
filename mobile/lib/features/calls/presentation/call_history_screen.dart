import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_back_button.dart';
import '../../../core/models/date_range_filter.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/date_range_filter_bar.dart';
import '../../../core/widgets/paginated_list_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/providers/auth_controller.dart';
import '../../dialer/presentation/dialer_screen.dart';
import '../../dialer/presentation/disposition_sheet.dart';
import '../../leads/presentation/lead_widgets.dart';
import '../data/call_models.dart';
import '../data/calls_repository.dart';
import 'recording_player.dart';

class CallHistoryScreen extends ConsumerStatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  ConsumerState<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends ConsumerState<CallHistoryScreen> {
  DateRangeFilter _range = const DateRangeFilter(DateRangePreset.thisWeek);
  CallStatus? _status;
  CallOutcome? _outcome;
  CallDirection? _direction;
  User? _salesperson;
  final _list = PaginatedListController();

  CallQuery get _query => CallQuery(
    range: _range,
    status: _status?.value,
    outcome: _outcome?.value,
    direction: _direction?.value,
    salespersonId: _salesperson?.id,
  );

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  Future<T?> _pickEnum<T extends LabeledEnum>(String title, List<T> values, T? current) async {
    final result = await showModalBottomSheet<({T? v})>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(title: const Text('Any'), onTap: () => Navigator.of(context).pop((v: null))),
            for (final v in values)
              ListTile(
                title: Text(v.label),
                trailing: v == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop((v: v)),
              ),
          ],
        ),
      ),
    );
    return result == null ? current : result.v;
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserProvider)?.role ?? UserRole.executive;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(role.isManagerOrAdmin ? 'Call history' : 'My call history'),
      ),
      body: ContentConstraint(
        child: Column(
          children: [
            DateRangeFilterBar(value: _range, onChanged: (r) => setState(() => _range = r)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilterChip(
                    label: Text(_status?.label ?? 'Status'),
                    selected: _status != null,
                    onSelected: (_) async {
                      final v = await _pickEnum('Call status', CallStatus.filterable, _status);
                      setState(() => _status = v);
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(_outcome?.label ?? 'Outcome'),
                    selected: _outcome != null,
                    onSelected: (_) async {
                      final v = await _pickEnum('Outcome', CallOutcome.values, _outcome);
                      setState(() => _outcome = v);
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(_direction?.label ?? 'Direction'),
                    selected: _direction != null,
                    onSelected: (_) async {
                      final v = await _pickEnum('Direction', CallDirection.values, _direction);
                      setState(() => _direction = v);
                    },
                  ),
                  if (role.isManagerOrAdmin) ...[
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(_salesperson?.fullName ?? 'Salesperson'),
                      selected: _salesperson != null,
                      onSelected: (_) async {
                        if (_salesperson != null) {
                          setState(() => _salesperson = null);
                          return;
                        }
                        final u = await showAssigneePicker(context, title: 'Filter by salesperson');
                        if (u != null) setState(() => _salesperson = u);
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: PaginatedListView<HumanCall>(
                controller: _list,
                resetKey: _query,
                fetch: (page) => ref.read(callsRepositoryProvider).list(_query, page: page),
                empty: const EmptyState(title: 'No calls in this period', icon: Icons.history),
                itemBuilder: (context, call, _) => CallTile(
                  call: call,
                  showSalesperson: role.isManagerOrAdmin,
                  onTap: () async {
                    await showCallDetailSheet(context, call.id);
                    _list.refresh();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet with full call details, notes, recording and actions.
Future<void> showCallDetailSheet(BuildContext context, String callId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CallDetailSheet(callId: callId),
  );
}

class _CallDetailSheet extends ConsumerWidget {
  const _CallDetailSheet({required this.callId});

  final String callId;

  Future<void> _addNote(BuildContext context, WidgetRef ref) async {
    final body = await showTextInputDialog(context, title: 'Add note', label: 'Note', maxLines: 4, confirmLabel: 'Add');
    if (body == null || body.isEmpty || !context.mounted) return;
    try {
      await ref.read(callsRepositoryProvider).addNote(callId, body);
      ref.invalidate(callDetailProvider(callId));
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(callDetailProvider(callId));
    final me = ref.watch(currentUserProvider);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: AsyncValueView<HumanCall>(
        value: detail,
        onRetry: () => ref.invalidate(callDetailProvider(callId)),
        data: (call) {
          final theme = Theme.of(context);
          final mine = call.salespersonId == me?.id;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(child: Text(call.displayName, style: theme.textTheme.titleLarge)),
                  StatusChip.callStatus(call.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${call.direction.label} · ${formatDateTime(call.startedAt ?? call.createdAt)}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              KeyValueRow(icon: Icons.person_outline, label: 'Salesperson', value: call.salespersonName),
              KeyValueRow(icon: Icons.phone_outlined, label: 'Number', value: call.phoneNumber),
              KeyValueRow(icon: Icons.timer_outlined, label: 'Talk time', value: formatDuration(call.talkSeconds)),
              KeyValueRow(
                icon: Icons.hourglass_bottom,
                label: 'Total duration',
                value: formatDuration(call.durationSeconds),
              ),
              KeyValueRow(icon: Icons.flag_outlined, label: 'Outcome', value: call.outcome?.label ?? 'Not logged'),
              KeyValueRow(icon: Icons.event_note_outlined, label: 'Follow-up', value: formatDateTime(call.followupAt)),
              KeyValueRow(icon: Icons.router_outlined, label: 'Provider', value: call.provider),
              KeyValueRow(icon: Icons.tag, label: 'Provider ref', value: call.providerCallId),
              if (call.failureReason != null)
                KeyValueRow(icon: Icons.error_outline, label: 'Failure', value: call.failureReason),
              if (call.recordingId != null) ...[
                const SizedBox(height: 12),
                Text('Recording', style: theme.textTheme.titleSmall),
                RecordingPlayer(recordingId: call.recordingId!),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text('Notes', style: theme.textTheme.titleSmall)),
                  TextButton.icon(
                    onPressed: () => _addNote(context, ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add note'),
                  ),
                ],
              ),
              if (call.notes.isEmpty)
                Text('No notes', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              for (final n in call.notes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(n.body),
                  subtitle: Text('${n.authorName ?? ''} · ${formatRelative(n.createdAt)}'),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (call.leadId != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          context.go('/leads/${call.leadId}');
                        },
                        child: const Text('Open lead'),
                      ),
                    ),
                  if (call.leadId != null && mine && call.status.isTerminal) const SizedBox(width: 12),
                  if (mine && call.status.isTerminal)
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final updated = await showDispositionSheet(context, call);
                          if (updated != null) ref.invalidate(callDetailProvider(callId));
                        },
                        child: Text(call.outcome == null ? 'Log outcome' : 'Update outcome'),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
