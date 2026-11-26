import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../leads/presentation/lead_form_screen.dart' show validateEmail, validatePhone;
import '../data/team_models.dart';
import '../data/team_repository.dart';

/// Admin: create a user (no [userId]) or edit role, team, calling number and status.
class UserFormScreen extends ConsumerStatefulWidget {
  const UserFormScreen({super.key, this.userId});

  final String? userId;

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _calling = TextEditingController();
  UserRole _role = UserRole.executive;
  String? _teamId;
  bool _active = true;
  bool _loading = false;
  bool _saving = false;
  Object? _error;

  bool get _isNew => widget.userId == null;

  @override
  void initState() {
    super.initState();
    if (!_isNew) _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _phone, _calling]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final u = await ref.read(teamRepositoryProvider).user(widget.userId!);
      _name.text = u.fullName;
      _email.text = u.email;
      _phone.text = u.phone ?? '';
      _calling.text = u.callingNumber ?? '';
      setState(() {
        _role = u.role;
        _teamId = u.teamId;
        _active = u.isActive;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'full_name': _name.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'calling_number': _calling.text.trim().isEmpty ? null : _calling.text.trim(),
      'role': _role.value,
      'team_id': _teamId,
      if (_password.text.isNotEmpty) 'password': _password.text,
      if (!_isNew) 'is_active': _active,
    };
    try {
      final repo = ref.read(teamRepositoryProvider);
      if (_isNew) {
        await repo.createUser(body);
      } else {
        await repo.updateUser(widget.userId!, body);
      }
      ref.invalidate(assignableUsersProvider);
      ref.invalidate(teamsProvider);
      if (!mounted) return;
      showSnack(context, _isNew ? 'User created' : 'User updated');
      context.pop();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(teamsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Add user' : 'Edit user')),
      body: _loading
          ? const LoadingView()
          : _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ContentConstraint(
                    maxWidth: 560,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Full name *'),
                          validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a name' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Work email *'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Email is required' : validateEmail(v),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: _isNew ? 'Initial password *' : 'New password',
                            helperText: _isNew ? 'At least 8 characters' : 'Leave blank to keep the current password',
                          ),
                          validator: (v) {
                            final value = v ?? '';
                            if (_isNew && value.length < 8) return 'At least 8 characters';
                            if (!_isNew && value.isNotEmpty && value.length < 8) return 'At least 8 characters';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'Phone'),
                          validator: (v) => validatePhone(v, required: false),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _calling,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Calling number',
                            helperText: 'The phone the telephony provider rings first for bridged calls',
                          ),
                          validator: (v) => validatePhone(v, required: false),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<UserRole>(
                          initialValue: _role,
                          decoration: const InputDecoration(labelText: 'Role'),
                          items: [for (final r in UserRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
                          onChanged: (v) => setState(() => _role = v ?? _role),
                        ),
                        const SizedBox(height: 12),
                        AsyncValueView<List<Team>>(
                          value: teams,
                          compactError: true,
                          onRetry: () => ref.invalidate(teamsProvider),
                          loading: const LinearProgressIndicator(),
                          data: (list) => DropdownButtonFormField<String?>(
                            initialValue: list.any((t) => t.id == _teamId) ? _teamId : null,
                            decoration: const InputDecoration(labelText: 'Team'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('No team')),
                              for (final t in list) DropdownMenuItem<String?>(value: t.id, child: Text(t.name)),
                            ],
                            onChanged: (v) => setState(() => _teamId = v),
                          ),
                        ),
                        if (!_isNew)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Active'),
                            subtitle: const Text('Inactive users can\'t sign in; their history is kept'),
                            value: _active,
                            onChanged: (v) => setState(() => _active = v),
                          ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_isNew ? 'Create user' : 'Save changes'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
