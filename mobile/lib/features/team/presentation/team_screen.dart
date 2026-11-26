import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_back_button.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/paginated_list_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/providers/auth_controller.dart';
import '../../leads/presentation/lead_widgets.dart';
import '../data/team_models.dart';
import '../data/team_repository.dart';

class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  final _users = PaginatedListController();
  Timer? _debounce;
  String? _q;
  UserRole? _role;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _users.dispose();
    super.dispose();
  }

  Future<void> _createTeam() async {
    final result = await showDialog<({String name, String? department, User? manager})>(
      context: context,
      builder: (_) => const _TeamDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(teamRepositoryProvider)
          .createTeam(name: result.name, department: result.department, managerId: result.manager?.id);
      ref.invalidate(teamsProvider);
      if (mounted) showSnack(context, 'Team created');
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(currentUserProvider)?.role.isAdmin ?? false;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(isAdmin ? 'Team management' : 'My team'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'People'),
            Tab(text: 'Teams'),
          ],
        ),
      ),
      floatingActionButton: !isAdmin
          ? null
          : _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/team/users/new');
                _users.refresh();
              },
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add user'),
            )
          : FloatingActionButton.extended(
              onPressed: _createTeam,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('New team'),
            ),
      body: TabBarView(
        controller: _tabs,
        children: [
          ContentConstraint(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search people'),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 350), () {
                        setState(() => _q = v.trim().isEmpty ? null : v.trim());
                      });
                    },
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Everyone'),
                        selected: _role == null,
                        onSelected: (_) => setState(() => _role = null),
                      ),
                      for (final r in UserRole.values)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            label: Text(r.label),
                            selected: _role == r,
                            onSelected: (_) => setState(() => _role = r),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: PaginatedListView<User>(
                    controller: _users,
                    resetKey: (_q, _role),
                    fetch: (page) => ref.read(teamRepositoryProvider).users(q: _q, role: _role?.value, page: page),
                    empty: const EmptyState(title: 'No people found', icon: Icons.groups_outlined),
                    itemBuilder: (context, u, _) => ListTile(
                      leading: AppAvatar(name: u.fullName),
                      title: Text(u.fullName),
                      subtitle: Text([u.email, if (u.teamName != null) u.teamName!].join(' · ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusChip(
                            label: u.role.label,
                            color: u.role == UserRole.admin
                                ? AppColors.ai
                                : u.role == UserRole.manager
                                ? AppColors.primary
                                : AppColors.teal,
                            dense: true,
                          ),
                          if (!u.isActive) ...[
                            const SizedBox(width: 6),
                            const StatusChip(label: 'Inactive', color: AppColors.neutral, dense: true),
                          ],
                        ],
                      ),
                      onTap: isAdmin
                          ? () async {
                              await context.push('/team/users/${u.id}');
                              _users.refresh();
                            }
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ContentConstraint(child: _TeamsTab(isAdmin: isAdmin)),
        ],
      ),
    );
  }
}

class _TeamsTab extends ConsumerWidget {
  const _TeamsTab({required this.isAdmin});

  final bool isAdmin;

  Future<void> _edit(BuildContext context, WidgetRef ref, Team team) async {
    final result = await showDialog<({String name, String? department, User? manager})>(
      context: context,
      builder: (_) => _TeamDialog(team: team),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(teamRepositoryProvider).updateTeam(team.id, {
        'name': result.name,
        'department': result.department,
        if (result.manager != null) 'manager_id': result.manager!.id,
      });
      ref.invalidate(teamsProvider);
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(teamsProvider),
      child: AsyncValueView<List<Team>>(
        value: ref.watch(teamsProvider),
        onRetry: () => ref.invalidate(teamsProvider),
        data: (teams) => teams.isEmpty
            ? ListView(
                children: const [
                  SizedBox(
                    height: 360,
                    child: EmptyState(title: 'No teams yet', icon: Icons.groups_outlined),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
                itemCount: teams.length,
                separatorBuilder: (_, _) => const Divider(indent: 72),
                itemBuilder: (context, i) {
                  final t = teams[i];
                  return ListTile(
                    leading: AppAvatar(name: t.name, icon: Icons.groups_outlined),
                    title: Text(t.name),
                    subtitle: Text(
                      [
                        if (t.department != null) t.department!,
                        'Manager: ${t.managerName ?? '—'}',
                        '${t.memberCount} member(s)',
                      ].join(' · '),
                    ),
                    trailing: isAdmin ? const Icon(Icons.edit_outlined) : null,
                    onTap: isAdmin ? () => _edit(context, ref, t) : null,
                  );
                },
              ),
      ),
    );
  }
}

class _TeamDialog extends StatefulWidget {
  const _TeamDialog({this.team});

  final Team? team;

  @override
  State<_TeamDialog> createState() => _TeamDialogState();
}

class _TeamDialogState extends State<_TeamDialog> {
  late final _name = TextEditingController(text: widget.team?.name);
  late final _department = TextEditingController(text: widget.team?.department);
  User? _manager;

  @override
  void dispose() {
    _name.dispose();
    _department.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.team == null ? 'New team' : 'Edit team'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Team name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _department,
            decoration: const InputDecoration(labelText: 'Department'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.manage_accounts_outlined),
            title: Text(_manager?.fullName ?? widget.team?.managerName ?? 'No manager'),
            subtitle: const Text('Manager'),
            onTap: () async {
              final u = await showAssigneePicker(context, title: 'Select manager');
              if (u != null) setState(() => _manager = u);
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.of(context).pop((
              name: _name.text.trim(),
              department: _department.text.trim().isEmpty ? null : _department.text.trim(),
              manager: _manager,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
