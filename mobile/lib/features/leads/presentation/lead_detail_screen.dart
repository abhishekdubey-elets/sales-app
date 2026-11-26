import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/providers/auth_controller.dart';
import '../../dialer/call_launcher.dart';
import '../../followups/data/followups_repository.dart';
import '../data/lead_models.dart';
import '../data/leads_repository.dart';
import 'lead_widgets.dart';

class LeadDetailScreen extends ConsumerWidget {
  const LeadDetailScreen({super.key, required this.leadId});

  final String leadId;

  void _refreshAll(WidgetRef ref) {
    ref.invalidate(leadDetailProvider(leadId));
    ref.invalidate(leadTimelineProvider(leadId));
    ref.invalidate(leadCallsProvider(leadId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lead = ref.watch(leadDetailProvider(leadId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lead'),
        actions: [if (lead.value != null) _LeadMenu(lead: lead.value!, onChanged: () => _refreshAll(ref))],
      ),
      body: AsyncValueView<Lead>(
        value: lead,
        onRetry: () => ref.invalidate(leadDetailProvider(leadId)),
        data: (l) => RefreshIndicator(
          onRefresh: () async => _refreshAll(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              ContentConstraint(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(lead: l, onChanged: () => _refreshAll(ref)),
                    const SizedBox(height: 12),
                    _InfoCard(lead: l),
                    SectionHeader(
                      title: 'Calls',
                      subtitle: 'Human and AI calls to this lead',
                      trailing: IconButton(
                        tooltip: 'Refresh',
                        onPressed: () => ref.invalidate(leadCallsProvider(leadId)),
                        icon: const Icon(Icons.refresh, size: 20),
                      ),
                    ),
                    _CallsCard(leadId: leadId),
                    const SectionHeader(title: 'Activity'),
                    _TimelineCard(leadId: leadId),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.lead, required this.onChanged});

  final Lead lead;
  final VoidCallback onChanged;

  Future<void> _changeStatus(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<LeadStatus>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final s in LeadStatus.values)
              ListTile(
                leading: StatusChip.leadStatus(s),
                trailing: s == lead.status ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(s),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == lead.status || !context.mounted) return;
    await _patch(context, ref, {'status': picked.value}, 'Status updated to ${picked.label}');
  }

  Future<void> _changePriority(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<LeadPriority>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final p in LeadPriority.values)
              ListTile(
                leading: StatusChip.priority(p),
                trailing: p == lead.priority ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(p),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == lead.priority || !context.mounted) return;
    await _patch(context, ref, {'priority': picked.value}, 'Priority set to ${picked.label}');
  }

  Future<void> _patch(BuildContext context, WidgetRef ref, Map<String, dynamic> body, String done) async {
    try {
      await ref.read(leadsRepositoryProvider).update(lead.id, body);
      if (context.mounted) showSnack(context, done);
      onChanged();
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _toggleFavourite(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(leadsRepositoryProvider).setFavourite(lead.id, !lead.isFavourite);
      onChanged();
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _scheduleFollowup(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: now.add(const Duration(days: 1)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 11, minute: 0));
    if (time == null || !context.mounted) return;
    final note = await showTextInputDialog(context, title: 'Follow-up note', label: 'What to discuss (optional)');
    if (note == null || !context.mounted) return;
    final due = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    try {
      await ref.read(followupsRepositoryProvider).create(leadId: lead.id, dueAt: due, note: note.isEmpty ? null : note);
      if (context.mounted) showSnack(context, 'Follow-up scheduled for ${formatDateTime(due)}');
      onChanged();
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppAvatar(name: lead.fullName, radius: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lead.fullName, style: theme.textTheme.titleLarge),
                      if (lead.subtitle.isNotEmpty)
                        Text(
                          lead.subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: lead.isFavourite ? 'Remove from favourites' : 'Add to favourites',
                  onPressed: () => _toggleFavourite(context, ref),
                  icon: Icon(
                    lead.isFavourite ? Icons.star : Icons.star_border,
                    color: lead.isFavourite ? const Color(0xFFE0A100) : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _changeStatus(context, ref),
                  child: StatusChip.leadStatus(lead.status),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _changePriority(context, ref),
                  child: StatusChip.priority(lead.priority),
                ),
                if (lead.optedOut) const StatusChip(label: 'Opted out', color: AppColors.danger, icon: Icons.block),
                if (lead.consentStatus == ConsentStatus.granted)
                  const StatusChip(label: 'Consent given', color: AppColors.success, icon: Icons.verified_outlined),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: lead.optedOut
                        ? null
                        : () => launchCall(context, ref, leadId: lead.id, displayName: lead.fullName),
                    icon: const Icon(Icons.call),
                    label: Text(lead.optedOut ? 'Opted out' : 'Call'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _scheduleFollowup(context, ref),
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('Follow-up'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    return InfoCard(
      title: 'Details',
      child: Column(
        children: [
          KeyValueRow(icon: Icons.phone_outlined, label: 'Phone', value: lead.displayPhone),
          if (lead.alternatePhone != null)
            KeyValueRow(icon: Icons.phone_forwarded_outlined, label: 'Alternate', value: lead.alternatePhone),
          KeyValueRow(icon: Icons.mail_outline, label: 'Email', value: lead.email),
          KeyValueRow(icon: Icons.badge_outlined, label: 'Designation', value: lead.designation),
          KeyValueRow(icon: Icons.factory_outlined, label: 'Industry', value: lead.industry),
          KeyValueRow(icon: Icons.place_outlined, label: 'Location', value: lead.location),
          KeyValueRow(icon: Icons.input_outlined, label: 'Source', value: lead.source),
          KeyValueRow(icon: Icons.person_outline, label: 'Assigned to', value: lead.assignedToName ?? 'Unassigned'),
          KeyValueRow(icon: Icons.history, label: 'Last called', value: formatDateTime(lead.lastCalledAt)),
          KeyValueRow(
            icon: Icons.event_note_outlined,
            label: 'Next follow-up',
            value: formatDateTime(lead.nextFollowupAt),
          ),
          KeyValueRow(icon: Icons.verified_user_outlined, label: 'Consent', value: lead.consentStatus.label),
          KeyValueRow(icon: Icons.notes_outlined, label: 'Remarks', value: lead.remarks),
        ],
      ),
    );
  }
}

class _CallsCard extends ConsumerWidget {
  const _CallsCard({required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: AsyncValueView<List<UnifiedCall>>(
        value: ref.watch(leadCallsProvider(leadId)),
        compactError: true,
        onRetry: () => ref.invalidate(leadCallsProvider(leadId)),
        loading: const SizedBox(height: 100, child: LoadingView()),
        data: (calls) {
          if (calls.isEmpty) {
            return const SizedBox(
              height: 120,
              child: EmptyState(title: 'No calls yet', icon: Icons.call_outlined),
            );
          }
          return Column(
            children: [
              for (final c in calls)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: (c.isAi ? AppColors.ai : AppColors.primary).withValues(alpha: 0.12),
                    foregroundColor: c.isAi ? AppColors.ai : AppColors.primary,
                    child: Icon(c.isAi ? Icons.smart_toy_outlined : Icons.headset_mic_outlined, size: 20),
                  ),
                  title: Text(
                    c.isAi
                        ? 'AI agent call${c.agentName != null ? ' · ${c.agentName}' : ''}${c.campaignName != null ? ' · ${c.campaignName}' : ''}'
                        : '${c.direction == 'inbound' ? 'Inbound' : 'Outbound'} · ${c.salespersonName ?? 'Salesperson'}',
                  ),
                  subtitle: Text(
                    [
                      formatDateTime(c.startedAt),
                      if (c.durationSeconds > 0) formatDuration(c.durationSeconds),
                      if (c.outcome != null) c.outcome!.label,
                      if (c.interestLevel != null) '${c.interestLevel!.label} interest',
                      if (c.summary != null) c.summary!,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: StatusChip.callStatus(c.status, dense: true),
                  onTap: c.isAi ? () => context.go('/ai/calls/${c.id}') : null,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TimelineCard extends ConsumerWidget {
  const _TimelineCard({required this.leadId});

  final String leadId;

  static IconData _icon(String type) => switch (type) {
    'created' => Icons.add_circle_outline,
    'assigned' => Icons.assignment_ind_outlined,
    'status_changed' => Icons.swap_horiz,
    'human_call' => Icons.call_outlined,
    'ai_call' => Icons.smart_toy_outlined,
    'note' => Icons.sticky_note_2_outlined,
    'followup' => Icons.event_note_outlined,
    'handoff' => Icons.support_agent,
    'opt_out' => Icons.block,
    'imported' => Icons.upload_file_outlined,
    _ => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: AsyncValueView<List<TimelineItem>>(
        value: ref.watch(leadTimelineProvider(leadId)),
        compactError: true,
        onRetry: () => ref.invalidate(leadTimelineProvider(leadId)),
        loading: const SizedBox(height: 100, child: LoadingView()),
        data: (items) {
          if (items.isEmpty) {
            return const SizedBox(
              height: 120,
              child: EmptyState(title: 'No activity yet', icon: Icons.timeline),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 56,
                          child: Column(
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 12),
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(_icon(items[i].type), size: 16, color: theme.colorScheme.primary),
                              ),
                              if (i < items.length - 1)
                                Expanded(child: Container(width: 2, color: theme.colorScheme.outlineVariant)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 12, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  items[i].title,
                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                if (items[i].description != null) Text(items[i].description!),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    formatRelative(items[i].at),
                                    if (items[i].actorName != null) items[i].actorName!,
                                  ].join(' · '),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LeadMenu extends ConsumerWidget {
  const _LeadMenu({required this.lead, required this.onChanged});

  final Lead lead;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProvider)?.role ?? UserRole.executive;
    return PopupMenuButton<String>(
      onSelected: (action) async {
        final repo = ref.read(leadsRepositoryProvider);
        switch (action) {
          case 'edit':
            await context.push('/leads/${lead.id}/edit');
            onChanged();
          case 'assign':
            final user = await showAssigneePicker(context);
            if (user == null || !context.mounted) return;
            try {
              await repo.update(lead.id, {'assigned_to_id': user.id});
              if (context.mounted) showSnack(context, 'Assigned to ${user.fullName}');
              onChanged();
            } catch (e) {
              if (context.mounted) showSnack(context, errorMessage(e), error: true);
            }
          case 'opt_out':
            final reason = await showTextInputDialog(
              context,
              title: 'Record opt-out',
              label: 'Reason (optional)',
              confirmLabel: 'Opt out',
            );
            if (reason == null || !context.mounted) return;
            try {
              await repo.optOut(lead.id, reason: reason.isEmpty ? null : reason);
              if (context.mounted) showSnack(context, 'Opt-out recorded. This number will not be called again.');
              onChanged();
            } catch (e) {
              if (context.mounted) showSnack(context, errorMessage(e), error: true);
            }
          case 'delete':
            final ok = await showConfirmDialog(
              context,
              title: 'Delete lead?',
              message: 'This permanently removes ${lead.fullName} and cannot be undone. Call records stay for audit.',
              confirmLabel: 'Delete',
              destructive: true,
            );
            if (!ok || !context.mounted) return;
            try {
              await repo.delete(lead.id);
              if (context.mounted) {
                showSnack(context, 'Lead deleted');
                context.go('/leads');
              }
            } catch (e) {
              if (context.mounted) showSnack(context, errorMessage(e), error: true);
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit')),
        ),
        if (role.isManagerOrAdmin)
          const PopupMenuItem(
            value: 'assign',
            child: ListTile(leading: Icon(Icons.assignment_ind_outlined), title: Text('Assign')),
          ),
        if (!lead.optedOut)
          const PopupMenuItem(
            value: 'opt_out',
            child: ListTile(leading: Icon(Icons.block), title: Text('Record opt-out')),
          ),
        if (role.isAdmin)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
          ),
      ],
    );
  }
}
