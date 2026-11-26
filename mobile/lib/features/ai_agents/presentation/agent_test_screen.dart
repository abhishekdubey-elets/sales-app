import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value_view.dart';
import '../data/ai_models.dart';
import '../data/ai_repository.dart';

/// Text-only rehearsal of an agent's prompt (`/ai/agents/{id}/test-reply`).
/// No call is placed; this exercises the same LLM configuration as live calls.
class AgentTestScreen extends ConsumerStatefulWidget {
  const AgentTestScreen({super.key, required this.agentId});

  final String agentId;

  @override
  ConsumerState<AgentTestScreen> createState() => _AgentTestScreenState();
}

class _Msg {
  const _Msg(this.role, this.text, {this.actions = const [], this.error = false});

  final String role; // user | assistant
  final String text;
  final List<String> actions;
  final bool error;
}

class _AgentTestScreenState extends ConsumerState<AgentTestScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[];
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final history = [
      for (final m in _messages.where((m) => !m.error)) {'role': m.role, 'text': m.text},
    ];
    setState(() {
      _messages.add(_Msg('user', text));
      _sending = true;
      _input.clear();
    });
    _scrollDown();
    try {
      final reply = await ref.read(aiRepositoryProvider).testReply(widget.agentId, text, history);
      setState(() => _messages.add(_Msg('assistant', reply.reply, actions: reply.actions)));
    } catch (e) {
      setState(() => _messages.add(_Msg('assistant', errorMessage(e), error: true)));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final agent = ref.watch(aiAgentProvider(widget.agentId));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: AsyncValueView<AIAgent>(
          value: agent,
          loading: const Text('Rehearse agent'),
          compactError: true,
          data: (a) => Text('Rehearse · ${a.name}'),
        ),
        actions: [
          IconButton(
            tooltip: 'Reset conversation',
            onPressed: _messages.isEmpty ? null : () => setState(_messages.clear),
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.ai.withValues(alpha: 0.08),
            padding: const EdgeInsets.all(12),
            child: const Text(
              'Type what a prospect might say. Replies come from the configured language model with this agent\'s '
              'prompt and knowledge base. Nothing is dialled.',
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Start with something like “Hello, who is this?”',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _messages.length) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        );
                      }
                      final m = _messages[i];
                      final mine = m.role == 'user';
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 520),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: m.error
                                ? theme.colorScheme.error.withValues(alpha: 0.1)
                                : mine
                                ? theme.colorScheme.primary
                                : AppColors.ai.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.text,
                                style: TextStyle(
                                  color: m.error
                                      ? theme.colorScheme.error
                                      : mine
                                      ? Colors.white
                                      : null,
                                ),
                              ),
                              if (m.actions.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    for (final a in m.actions)
                                      Chip(
                                        visualDensity: VisualDensity.compact,
                                        avatar: const Icon(Icons.bolt, size: 14),
                                        label: Text(a),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: 'Say something as the prospect…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
