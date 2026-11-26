import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/chip_list_editor.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/ai_models.dart';
import '../data/ai_repository.dart';

/// Create (no [agentId]) or edit an AI agent. Managers see it read-only.
class AgentEditorScreen extends ConsumerStatefulWidget {
  const AgentEditorScreen({super.key, this.agentId});

  final String? agentId;

  @override
  ConsumerState<AgentEditorScreen> createState() => _AgentEditorScreenState();
}

class _AgentEditorScreenState extends ConsumerState<AgentEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _personality = TextEditingController();
  final _voiceId = TextEditingController();
  final _greeting = TextEditingController();
  final _systemPrompt = TextEditingController();
  final _knowledge = TextEditingController();
  final _maxMinutes = TextEditingController(text: '5');
  final _retryDelay = TextEditingController(text: '60');

  AgentLanguage _language = AgentLanguage.englishIndia;
  double _speed = 1.0;
  List<String> _objectives = [];
  List<String> _handoff = [];
  int _maxAttempts = 3;
  Set<String> _retryOn = {'busy', 'not_answered'};
  bool _recording = true;
  bool _isActive = true;

  bool _loading = false;
  bool _saving = false;
  Object? _loadError;

  bool get _isNew => widget.agentId == null;

  @override
  void initState() {
    super.initState();
    if (!_isNew) _load();
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _personality,
      _voiceId,
      _greeting,
      _systemPrompt,
      _knowledge,
      _maxMinutes,
      _retryDelay,
    ]) {
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
      final agent = await ref.read(aiRepositoryProvider).agent(widget.agentId!);
      _apply(agent.config);
      setState(() {
        _isActive = agent.isActive;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  void _apply(AIAgentConfig c) {
    _name.text = c.name;
    _description.text = c.description;
    _personality.text = c.personality;
    _voiceId.text = c.voiceId;
    _greeting.text = c.greeting;
    _systemPrompt.text = c.systemPrompt;
    _knowledge.text = c.knowledgeBase;
    _maxMinutes.text = (c.maxCallDurationSeconds / 60).toStringAsFixed(c.maxCallDurationSeconds % 60 == 0 ? 0 : 1);
    _retryDelay.text = '${c.retryRules.retryDelayMinutes}';
    setState(() {
      _language = c.language;
      _speed = c.speakingSpeed.clamp(0.5, 2.0);
      _objectives = [...c.objectives];
      _handoff = [...c.handoffConditions];
      _maxAttempts = c.retryRules.maxAttempts.clamp(1, 10);
      _retryOn = {...c.retryRules.retryOn};
      _recording = c.recordingEnabled;
    });
  }

  AIAgentConfig _config() => AIAgentConfig(
    name: _name.text.trim(),
    description: _description.text.trim(),
    personality: _personality.text.trim(),
    language: _language,
    voiceId: _voiceId.text.trim(),
    speakingSpeed: double.parse(_speed.toStringAsFixed(2)),
    systemPrompt: _systemPrompt.text.trim(),
    knowledgeBase: _knowledge.text.trim(),
    objectives: _objectives,
    greeting: _greeting.text.trim(),
    maxCallDurationSeconds: ((double.tryParse(_maxMinutes.text) ?? 5) * 60).round(),
    retryRules: RetryRules(
      maxAttempts: _maxAttempts,
      retryDelayMinutes: int.tryParse(_retryDelay.text) ?? 60,
      retryOn: _retryOn.toList(),
    ),
    handoffConditions: _handoff,
    recordingEnabled: _recording,
  );

  Future<void> _pickTemplate() async {
    try {
      final templates = await runWithProgress(context, () => ref.read(aiRepositoryProvider).templates());
      if (!mounted) return;
      final picked = await showModalBottomSheet<AIAgentConfig>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Start from a template', style: Theme.of(context).textTheme.titleMedium),
              ),
              if (templates.isEmpty) const ListTile(title: Text('No templates available')),
              for (final t in templates)
                ListTile(
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: Text(t.name),
                  subtitle: Text(t.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.of(context).pop(t),
                ),
            ],
          ),
        ),
      );
      if (picked != null) _apply(picked);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final repo = ref.read(aiRepositoryProvider);
    try {
      final config = _config();
      final AIAgent saved;
      if (_isNew) {
        saved = await repo.createAgent(config);
      } else {
        saved = await repo.updateAgent(widget.agentId!, {...config.toJson(), 'is_active': _isActive});
        ref.invalidate(aiAgentProvider(widget.agentId!));
      }
      ref.invalidate(aiAgentsProvider);
      if (!mounted) return;
      showSnack(context, _isNew ? 'Agent created' : 'Agent saved');
      if (_isNew) context.pushReplacement('/ai/agents/${saved.id}');
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _archive() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Archive agent?',
      message: 'Archived agents can\'t be used in new campaigns. Their call history is kept.',
      confirmLabel: 'Archive',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(aiRepositoryProvider).archiveAgent(widget.agentId!);
      ref.invalidate(aiAgentsProvider);
      if (mounted) {
        showSnack(context, 'Agent archived');
        context.go('/ai?tab=agents');
      }
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Widget _text(
    TextEditingController c,
    String label, {
    String? hint,
    int maxLines = 1,
    bool required = false,
    bool readOnly = false,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        readOnly: readOnly,
        maxLines: maxLines,
        minLines: maxLines > 1 ? 2 : 1,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          alignLabelWithHint: maxLines > 1,
        ),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(currentUserProvider)?.role.isAdmin ?? false;
    final readOnly = !isAdmin;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New AI agent' : (readOnly ? 'AI agent' : 'Edit AI agent')),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Rehearse in text',
              onPressed: () => context.go('/ai/agents/${widget.agentId}/test'),
              icon: const Icon(Icons.chat_outlined),
            ),
          if (!_isNew && isAdmin)
            IconButton(tooltip: 'Archive', onPressed: _archive, icon: const Icon(Icons.archive_outlined)),
          if (isAdmin) TextButton(onPressed: _saving || _loading ? null : _save, child: const Text('Save')),
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
                    maxWidth: 720,
                    child: AbsorbPointer(
                      absorbing: readOnly,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_isNew)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: OutlinedButton.icon(
                                onPressed: _pickTemplate,
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: const Text('Start from an Elets template'),
                              ),
                            ),
                          InfoCard(
                            title: 'Identity',
                            child: Column(
                              children: [
                                _text(_name, 'Agent name', required: true, readOnly: readOnly),
                                _text(_description, 'Description', maxLines: 2, readOnly: readOnly),
                                _text(
                                  _personality,
                                  'Personality',
                                  hint: 'Warm, concise, professional; never pushy',
                                  maxLines: 2,
                                  readOnly: readOnly,
                                ),
                                if (!_isNew)
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Active'),
                                    value: _isActive,
                                    onChanged: (v) => setState(() => _isActive = v),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          InfoCard(
                            title: 'Voice',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('Language', style: theme.textTheme.labelLarge),
                                const SizedBox(height: 8),
                                SegmentedButton<AgentLanguage>(
                                  segments: [
                                    for (final l in AgentLanguage.values) ButtonSegment(value: l, label: Text(l.label)),
                                  ],
                                  selected: {_language},
                                  onSelectionChanged: (s) => setState(() => _language = s.first),
                                ),
                                const SizedBox(height: 12),
                                _text(
                                  _voiceId,
                                  'Voice ID',
                                  helper: 'Voice identifier from your TTS provider',
                                  readOnly: readOnly,
                                ),
                                Row(
                                  children: [
                                    Text('Speaking speed', style: theme.textTheme.labelLarge),
                                    const Spacer(),
                                    Text('${_speed.toStringAsFixed(2)}×'),
                                  ],
                                ),
                                Slider(
                                  value: _speed,
                                  min: 0.5,
                                  max: 2.0,
                                  divisions: 15,
                                  label: '${_speed.toStringAsFixed(1)}×',
                                  onChanged: (v) => setState(() => _speed = v),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          InfoCard(
                            title: 'Conversation',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _text(
                                  _greeting,
                                  'Greeting',
                                  hint: 'Spoken after the mandatory AI disclosure',
                                  maxLines: 2,
                                  readOnly: readOnly,
                                  helper: 'The AI disclosure (and recording notice) is always played first.',
                                ),
                                _text(_systemPrompt, 'System prompt', maxLines: 8, required: true, readOnly: readOnly),
                                _text(
                                  _knowledge,
                                  'Knowledge base',
                                  hint: 'Facts about Elets events, media offerings, pricing guidance…',
                                  maxLines: 8,
                                  readOnly: readOnly,
                                ),
                                ChipListEditor(
                                  label: 'Conversation objectives',
                                  hint: 'e.g. Confirm interest in eGov Summit sponsorship',
                                  values: _objectives,
                                  enabled: !readOnly,
                                  onChanged: (v) => setState(() => _objectives = v),
                                ),
                                const SizedBox(height: 16),
                                ChipListEditor(
                                  label: 'Human handoff conditions',
                                  hint: 'e.g. Prospect asks for pricing or a custom package',
                                  values: _handoff,
                                  enabled: !readOnly,
                                  onChanged: (v) => setState(() => _handoff = v),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          InfoCard(
                            title: 'Call rules',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _maxMinutes,
                                  readOnly: readOnly,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                  decoration: const InputDecoration(labelText: 'Maximum call duration (minutes)'),
                                  validator: (v) {
                                    final n = double.tryParse(v ?? '');
                                    if (n == null || n < 0.5 || n > 30) return 'Between 0.5 and 30 minutes';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(child: Text('Max attempts per lead', style: theme.textTheme.bodyMedium)),
                                    IconButton(
                                      onPressed: _maxAttempts > 1 ? () => setState(() => _maxAttempts--) : null,
                                      icon: const Icon(Icons.remove_circle_outline),
                                    ),
                                    Text('$_maxAttempts', style: theme.textTheme.titleMedium),
                                    IconButton(
                                      onPressed: _maxAttempts < 10 ? () => setState(() => _maxAttempts++) : null,
                                      icon: const Icon(Icons.add_circle_outline),
                                    ),
                                  ],
                                ),
                                TextFormField(
                                  controller: _retryDelay,
                                  readOnly: readOnly,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  decoration: const InputDecoration(labelText: 'Retry delay (minutes)'),
                                ),
                                const SizedBox(height: 12),
                                Text('Retry when the call is', style: theme.textTheme.labelLarge),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    for (final s in const [
                                      ('busy', 'Busy'),
                                      ('not_answered', 'Not answered'),
                                      ('failed', 'Failed'),
                                    ])
                                      FilterChip(
                                        label: Text(s.$2),
                                        selected: _retryOn.contains(s.$1),
                                        onSelected: (v) =>
                                            setState(() => v ? _retryOn.add(s.$1) : _retryOn.remove(s.$1)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Record calls'),
                                  subtitle: const Text(
                                    'Only where lawful and enabled by your admin. A recording notice is played.',
                                  ),
                                  value: _recording,
                                  onChanged: (v) => setState(() => _recording = v),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (isAdmin)
                            FilledButton(
                              onPressed: _saving ? null : _save,
                              child: _saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(_isNew ? 'Create agent' : 'Save changes'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
