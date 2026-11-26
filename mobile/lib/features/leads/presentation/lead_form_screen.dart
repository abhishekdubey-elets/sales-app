import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/lead_models.dart';
import '../data/leads_repository.dart';
import 'lead_widgets.dart';

final _phonePattern = RegExp(r'^\+?[0-9][0-9\s-]{8,16}$');
final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validatePhone(String? v, {bool required = true}) {
  final value = v?.trim() ?? '';
  if (value.isEmpty) return required ? 'Phone number is required' : null;
  if (!_phonePattern.hasMatch(value)) return 'Enter a valid phone number (10–15 digits)';
  return null;
}

String? validateEmail(String? v) {
  final value = v?.trim() ?? '';
  if (value.isEmpty) return null;
  return _emailPattern.hasMatch(value) ? null : 'Enter a valid email address';
}

/// Add lead (no [leadId]) or edit an existing one.
class LeadFormScreen extends ConsumerStatefulWidget {
  const LeadFormScreen({super.key, this.leadId});

  final String? leadId;

  @override
  ConsumerState<LeadFormScreen> createState() => _LeadFormScreenState();
}

class _LeadFormScreenState extends ConsumerState<LeadFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _c = {
    for (final k in [
      'full_name',
      'company_name',
      'phone',
      'alternate_phone',
      'email',
      'designation',
      'industry',
      'location',
      'source',
      'remarks',
    ])
      k: TextEditingController(),
  };
  LeadPriority _priority = LeadPriority.medium;
  ConsentStatus _consent = ConsentStatus.unknown;
  User? _assignee;
  String? _assigneeName;
  bool _loading = false;
  bool _saving = false;
  Object? _loadError;
  String? _duplicateLeadId;
  String? _duplicateOn;
  Map<String, String> _original = const {};

  bool get _isEdit => widget.leadId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final lead = await ref.read(leadsRepositoryProvider).get(widget.leadId!);
      final j = lead.toJson();
      for (final e in _c.entries) {
        e.value.text = (j[e.key] ?? '').toString();
      }
      _original = {for (final e in _c.entries) e.key: e.value.text};
      setState(() {
        _priority = lead.priority;
        _consent = lead.consentStatus;
        _assigneeName = lead.assignedToName;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _checkDuplicate() async {
    if (_isEdit) return;
    final phone = _c['phone']!.text.trim();
    final email = _c['email']!.text.trim();
    if (validatePhone(phone) != null && (email.isEmpty || validateEmail(email) != null)) return;
    try {
      final result = await ref
          .read(leadsRepositoryProvider)
          .checkDuplicate(
            phone: validatePhone(phone) == null ? phone : null,
            email: email.isNotEmpty && validateEmail(email) == null ? email : null,
          );
      if (!mounted) return;
      setState(() {
        _duplicateLeadId = result.duplicate ? result.leadId : null;
        _duplicateOn = result.matchedOn;
      });
    } catch (_) {
      // Pre-check only; the server enforces uniqueness on save anyway.
    }
  }

  Map<String, dynamic> _body() {
    final body = <String, dynamic>{
      for (final e in _c.entries)
        // When editing, only send fields the user changed: phone numbers may be
        // displayed masked and must never be written back in masked form.
        if (!_isEdit || _original[e.key] != e.value.text)
          e.key: e.value.text.trim().isEmpty ? null : e.value.text.trim(),
      'priority': _priority.value,
      'consent_status': _consent.value,
    };
    if (_assignee != null) body['assigned_to_id'] = _assignee!.id;
    return body;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final repo = ref.read(leadsRepositoryProvider);
    try {
      final Lead lead;
      if (_isEdit) {
        // PATCH with changed fields only; cleared fields are sent as null.
        lead = await repo.update(widget.leadId!, _body());
        ref.invalidate(leadDetailProvider(widget.leadId!));
      } else {
        lead = await repo.create(_body());
      }
      if (!mounted) return;
      showSnack(context, _isEdit ? 'Lead updated' : 'Lead created');
      if (_isEdit) {
        context.pop();
      } else {
        context.pushReplacement('/leads/${lead.id}');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'duplicate_lead' || e.isConflict) {
        setState(() {
          _duplicateLeadId = e.extra['duplicate_lead_id']?.toString();
          _duplicateOn = e.extra['matched_on']?.toString();
        });
      }
      showSnack(context, e.friendlyMessage, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    String key,
    String label, {
    IconData? icon,
    TextInputType? type,
    String? Function(String?)? validator,
    int maxLines = 1,
    VoidCallback? onBlur,
  }) {
    final field = TextFormField(
      controller: _c[key],
      keyboardType: type,
      maxLines: maxLines,
      textInputAction: maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
      decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon)),
      validator: validator,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: onBlur == null ? field : Focus(onFocusChange: (has) => has ? null : onBlur(), child: field),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserProvider)?.role ?? UserRole.executive;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit lead' : 'New lead'),
        actions: [
          TextButton(onPressed: _saving || _loading ? null : _save, child: const Text('Save')),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _loadError != null
          ? ErrorState(error: _loadError!, onRetry: _load)
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ContentConstraint(
                    maxWidth: 640,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_duplicateLeadId != null)
                          _DuplicateBanner(leadId: _duplicateLeadId!, matchedOn: _duplicateOn),
                        _field(
                          'full_name',
                          'Full name *',
                          icon: Icons.person_outline,
                          validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the lead\'s name' : null,
                        ),
                        _field('company_name', 'Company', icon: Icons.business_outlined),
                        _field('designation', 'Designation', icon: Icons.badge_outlined),
                        _field(
                          'phone',
                          'Phone number *',
                          icon: Icons.phone_outlined,
                          type: TextInputType.phone,
                          validator: (v) => _isEdit && (v?.contains('*') ?? false) ? null : validatePhone(v),
                          onBlur: _checkDuplicate,
                        ),
                        _field(
                          'alternate_phone',
                          'Alternate phone',
                          icon: Icons.phone_forwarded_outlined,
                          type: TextInputType.phone,
                          validator: (v) =>
                              _isEdit && (v?.contains('*') ?? false) ? null : validatePhone(v, required: false),
                        ),
                        _field(
                          'email',
                          'Email',
                          icon: Icons.mail_outline,
                          type: TextInputType.emailAddress,
                          validator: validateEmail,
                          onBlur: _checkDuplicate,
                        ),
                        _field('industry', 'Industry', icon: Icons.factory_outlined),
                        _field('location', 'Location', icon: Icons.place_outlined),
                        _field('source', 'Lead source', icon: Icons.input_outlined),
                        Text('Priority', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 8),
                        SegmentedButton<LeadPriority>(
                          segments: [
                            for (final p in LeadPriority.values) ButtonSegment(value: p, label: Text(p.label)),
                          ],
                          selected: {_priority},
                          onSelectionChanged: (s) => setState(() => _priority = s.first),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<ConsentStatus>(
                          initialValue: _consent,
                          decoration: const InputDecoration(
                            labelText: 'Calling consent',
                            prefixIcon: Icon(Icons.verified_user_outlined),
                            helperText: 'Required for AI calls when your admin enables consent checks.',
                          ),
                          items: [
                            for (final c in ConsentStatus.values) DropdownMenuItem(value: c, child: Text(c.label)),
                          ],
                          onChanged: (v) => setState(() => _consent = v ?? _consent),
                        ),
                        const SizedBox(height: 12),
                        if (role.isManagerOrAdmin)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.assignment_ind_outlined),
                            title: Text(_assignee?.fullName ?? _assigneeName ?? 'Unassigned'),
                            subtitle: const Text('Assigned salesperson'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              final u = await showAssigneePicker(context);
                              if (u != null) setState(() => _assignee = u);
                            },
                          ),
                        const SizedBox(height: 4),
                        _field('remarks', 'Remarks', icon: Icons.notes_outlined, maxLines: 3),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_isEdit ? 'Save changes' : 'Create lead'),
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

class _DuplicateBanner extends StatelessWidget {
  const _DuplicateBanner({required this.leadId, this.matchedOn});

  final String leadId;
  final String? matchedOn;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(child: Text('A lead with this ${matchedOn ?? 'phone or email'} already exists.')),
          TextButton(onPressed: () => context.go('/leads/$leadId'), child: const Text('Open existing')),
        ],
      ),
    );
  }
}
