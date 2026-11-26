import 'package:flutter/material.dart';

/// Editable list of short strings shown as chips (objectives, handoff conditions).
class ChipListEditor extends StatefulWidget {
  const ChipListEditor({
    super.key,
    required this.label,
    required this.values,
    required this.onChanged,
    this.hint,
    this.enabled = true,
  });

  final String label;
  final String? hint;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  @override
  State<ChipListEditor> createState() => _ChipListEditorState();
}

class _ChipListEditorState extends State<ChipListEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.values.contains(text)) return;
    widget.onChanged([...widget.values, text]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        if (widget.values.isEmpty)
          Text('None added', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in widget.values)
              InputChip(
                label: Text(v),
                onDeleted: widget.enabled ? () => widget.onChanged(widget.values.where((e) => e != v).toList()) : null,
              ),
          ],
        ),
        if (widget.enabled) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: widget.hint ?? 'Add and press Enter',
              suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _add),
            ),
            onSubmitted: (_) => _add(),
          ),
        ],
      ],
    );
  }
}
