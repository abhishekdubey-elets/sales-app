import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/paginated_list_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/providers/auth_controller.dart';
import '../../dialer/call_launcher.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../data/lead_models.dart';
import '../data/leads_repository.dart';
import 'lead_widgets.dart';

class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key});

  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  final _search = TextEditingController();
  final _list = PaginatedListController();
  final _listKey = GlobalKey<PaginatedListViewState<Lead>>();
  Timer? _debounce;

  String? _q;
  LeadStatus? _status;
  LeadPriority? _priority;
  String? _assigned; // null | me | unassigned
  bool _favourites = false;
  final Set<String> _selected = {};

  LeadQuery get _query => LeadQuery(
    q: _q,
    status: _status?.value,
    priority: _priority?.value,
    assignedTo: _assigned,
    favourites: _favourites,
  );

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _list.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = v.trim();
      if (q != (_q ?? '')) setState(() => _q = q.isEmpty ? null : q);
    });
  }

  void _toggle(Lead lead) => setState(() {
    if (!_selected.remove(lead.id)) _selected.add(lead.id);
  });

  Future<void> _bulkAssign() async {
    final user = await showAssigneePicker(context, title: 'Assign ${_selected.length} lead(s) to');
    if (user == null || !mounted) return;
    try {
      final count = await runWithProgress(
        context,
        () => ref.read(leadsRepositoryProvider).assign(_selected.toList(), user.id),
        message: 'Assigning leads…',
      );
      if (!mounted) return;
      showSnack(context, 'Assigned $count lead(s) to ${user.fullName}');
      setState(_selected.clear);
      _list.refresh();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final canManage = user?.role.isManagerOrAdmin ?? false;
    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
              title: Text('${_selected.length} selected'),
              actions: [
                TextButton.icon(
                  onPressed: _bulkAssign,
                  icon: const Icon(Icons.assignment_ind_outlined),
                  label: const Text('Assign'),
                ),
                const SizedBox(width: 8),
              ],
            )
          : AppBar(
              title: const Text('Leads'),
              actions: [
                if (canManage)
                  IconButton(
                    tooltip: 'Import leads',
                    onPressed: () => context.go('/leads/import'),
                    icon: const Icon(Icons.upload_file_outlined),
                  ),
                const NotificationBell(),
                const SizedBox(width: 8),
              ],
            ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/leads/new');
                _list.refresh();
              },
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add lead'),
            ),
      body: ContentConstraint(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search name, company, email or phone',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            _onSearch('');
                          },
                        ),
                ),
              ),
            ),
            _FilterBar(
              status: _status,
              priority: _priority,
              assigned: _assigned,
              favourites: _favourites,
              showAssignment: canManage,
              onStatus: (s) => setState(() => _status = s),
              onPriority: (p) => setState(() => _priority = p),
              onAssigned: (a) => setState(() => _assigned = a),
              onFavourites: (f) => setState(() => _favourites = f),
            ),
            if (canManage && !_selectionMode)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Text(
                  'Tip: long-press leads to select several and assign them.',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            Expanded(
              child: PaginatedListView<Lead>(
                key: _listKey,
                controller: _list,
                resetKey: _query,
                fetch: (page) => ref.read(leadsRepositoryProvider).list(_query, page: page),
                empty: EmptyState(
                  icon: Icons.people_alt_outlined,
                  title: _q != null || _status != null || _priority != null || _favourites || _assigned != null
                      ? 'No leads match these filters'
                      : 'No leads yet',
                  message: canManage ? 'Add a lead or import a CSV/Excel file.' : 'Leads assigned to you appear here.',
                ),
                itemBuilder: (context, lead, _) => LeadTile(
                  lead: lead,
                  selectionMode: _selectionMode,
                  selected: _selected.contains(lead.id),
                  onTap: _selectionMode ? () => _toggle(lead) : () => context.go('/leads/${lead.id}'),
                  onLongPress: canManage ? () => _toggle(lead) : null,
                  onCall: () => launchCall(context, ref, leadId: lead.id, displayName: lead.fullName),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.status,
    required this.priority,
    required this.assigned,
    required this.favourites,
    required this.showAssignment,
    required this.onStatus,
    required this.onPriority,
    required this.onAssigned,
    required this.onFavourites,
  });

  final LeadStatus? status;
  final LeadPriority? priority;
  final String? assigned;
  final bool favourites;
  final bool showAssignment;
  final ValueChanged<LeadStatus?> onStatus;
  final ValueChanged<LeadPriority?> onPriority;
  final ValueChanged<String?> onAssigned;
  final ValueChanged<bool> onFavourites;

  Future<void> _pick<T extends LabeledEnum>(
    BuildContext context,
    String title,
    List<T> values,
    T? current,
    ValueChanged<T?> onChanged,
  ) async {
    final result = await showModalBottomSheet<({T? value})>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              title: const Text('Any'),
              trailing: current == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop((value: null)),
            ),
            for (final v in values)
              ListTile(
                title: Text(v.label),
                trailing: current == v ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop((value: v)),
              ),
          ],
        ),
      ),
    );
    if (result != null) onChanged(result.value);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          FilterChip(
            label: Text(status?.label ?? 'Status'),
            selected: status != null,
            onSelected: (_) => _pick(context, 'Lead status', LeadStatus.values, status, onStatus),
            avatar: const Icon(Icons.filter_list, size: 16),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Text(priority == null ? 'Priority' : '${priority!.label} priority'),
            selected: priority != null,
            onSelected: (_) => _pick(context, 'Priority', LeadPriority.values, priority, onPriority),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Favourites'),
            selected: favourites,
            avatar: const Icon(Icons.star_border, size: 16),
            onSelected: onFavourites,
          ),
          if (showAssignment) ...[
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Assigned to me'),
              selected: assigned == 'me',
              onSelected: (v) => onAssigned(v ? 'me' : null),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Unassigned'),
              selected: assigned == 'unassigned',
              onSelected: (v) => onAssigned(v ? 'unassigned' : null),
            ),
          ],
        ],
      ),
    );
  }
}
