import 'package:flutter/material.dart';

import '../utils/formatters.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction, this.trailing, this.subtitle});

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          ?trailing,
          if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, required this.name, this.radius = 20, this.icon});

  final String name;
  final double radius;
  final IconData? icon;

  static const _palette = [
    Color(0xFF0A5BD3),
    Color(0xFF7A5AF8),
    Color(0xFF0E9384),
    Color(0xFFE08A00),
    Color(0xFFD92D6B),
    Color(0xFF2E90FA),
    Color(0xFF12A150),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _palette[name.hashCode.abs() % _palette.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.14),
      foregroundColor: color,
      child: icon != null
          ? Icon(icon, size: radius)
          : Text(
              initials(name),
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: radius * 0.75),
            ),
    );
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow({super.key, required this.label, required this.value, this.icon, this.trailing});

  final String label;
  final String? value;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
          ],
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text((value == null || value!.isEmpty) ? '—' : value!, style: theme.textTheme.bodyMedium)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Centers content and caps its width on tablets / web.
class ContentConstraint extends StatelessWidget {
  const ContentConstraint({super.key, required this.child, this.maxWidth = 900});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// A padded card with an optional title row.
class InfoCard extends StatelessWidget {
  const InfoCard({super.key, this.title, required this.child, this.trailing, this.padding = const EdgeInsets.all(16)});

  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(title!, style: theme.textTheme.titleSmall)),
                    ?trailing,
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
}

/// Wraps a long-running action with a blocking progress dialog.
Future<T> runWithProgress<T>(
  BuildContext context,
  Future<T> Function() action, {
  String message = 'Please wait…',
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    return await action();
  } finally {
    navigator.pop();
  }
}
