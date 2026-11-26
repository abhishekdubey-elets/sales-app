import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/file_pick.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/stat_card.dart';
import '../../auth/data/auth_models.dart';
import '../data/lead_models.dart';
import '../data/leads_repository.dart';
import 'lead_widgets.dart';

/// Upload a CSV/XLSX of leads, optionally assigning them all to one salesperson.
class LeadImportScreen extends ConsumerStatefulWidget {
  const LeadImportScreen({super.key});

  @override
  ConsumerState<LeadImportScreen> createState() => _LeadImportScreenState();
}

class _LeadImportScreenState extends ConsumerState<LeadImportScreen> {
  PickedFile? _file;
  User? _assignee;
  final _source = TextEditingController();
  bool _uploading = false;
  ImportResult? _result;

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final f = await pickSpreadsheet();
      if (f != null) setState(() => _file = f);
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t open the file: $e', error: true);
    }
  }

  Future<void> _upload() async {
    final f = _file;
    if (f == null) return;
    setState(() {
      _uploading = true;
      _result = null;
    });
    try {
      final result = await ref
          .read(leadsRepositoryProvider)
          .importFile(
            f.bytes,
            f.name,
            assigneeId: _assignee?.id,
            source: _source.text.trim().isEmpty ? null : _source.text.trim(),
          );
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _showTemplate() async {
    try {
      final text = await runWithProgress(context, () => ref.read(leadsRepositoryProvider).importTemplate());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('CSV template'),
          content: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.of(context).pop();
                showSnack(this.context, 'Template copied to clipboard');
              },
              child: const Text('Copy'),
            ),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Import leads')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentConstraint(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InfoCard(
                  title: '1. Choose a file',
                  trailing: TextButton(onPressed: _showTemplate, child: const Text('View template')),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'CSV or Excel (.xlsx). Recognised columns: full_name, company_name, phone, alternate_phone, '
                        'email, designation, industry, location, source, priority, remarks. '
                        'Rows whose phone or email already exists are skipped as duplicates.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _uploading ? null : _pick,
                        icon: const Icon(Icons.attach_file),
                        label: Text(_file == null ? 'Select file' : '${_file!.name} (${_file!.sizeLabel})'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                InfoCard(
                  title: '2. Options',
                  child: Column(
                    children: [
                      TextField(
                        controller: _source,
                        decoration: const InputDecoration(
                          labelText: 'Lead source (optional)',
                          hintText: 'e.g. eGov Summit 2026 registrations',
                          prefixIcon: Icon(Icons.input_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.assignment_ind_outlined),
                        title: Text(_assignee?.fullName ?? 'Don\'t assign'),
                        subtitle: const Text('Assign all imported leads to'),
                        trailing: _assignee == null
                            ? const Icon(Icons.chevron_right)
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(() => _assignee = null),
                              ),
                        onTap: () async {
                          final u = await showAssigneePicker(context);
                          if (u != null) setState(() => _assignee = u);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _file == null || _uploading ? null : _upload,
                  icon: _uploading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(_uploading ? 'Importing…' : 'Import leads'),
                ),
                if (result != null) ...[
                  const SizedBox(height: 24),
                  Text('Import result', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  StatGrid(
                    children: [
                      StatCard(label: 'Rows read', value: '${result.totalRows}', icon: Icons.table_rows_outlined),
                      StatCard(
                        label: 'Leads created',
                        value: '${result.created}',
                        icon: Icons.check_circle_outline,
                        color: AppColors.success,
                      ),
                      StatCard(
                        label: 'Duplicates skipped',
                        value: '${result.duplicates}',
                        icon: Icons.content_copy,
                        color: AppColors.warning,
                      ),
                      StatCard(
                        label: 'Rows with errors',
                        value: '${result.errors.length}',
                        icon: Icons.error_outline,
                        color: AppColors.danger,
                      ),
                    ],
                  ),
                  if (result.errors.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    InfoCard(
                      title: 'Errors',
                      child: Column(
                        children: [
                          for (final err in result.errors.take(200))
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Text('Row ${err.row}', style: theme.textTheme.labelMedium),
                              title: Text(err.error),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
