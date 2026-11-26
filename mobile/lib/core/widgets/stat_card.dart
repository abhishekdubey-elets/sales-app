import 'package:flutter/material.dart';

/// Dashboard metric tile: icon, big value, label, optional caption.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.caption,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                  const Spacer(),
                  if (onTap != null) Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (caption != null) ...[
                const SizedBox(height: 2),
                Text(caption!, style: theme.textTheme.labelSmall?.copyWith(color: accent)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Responsive grid of [StatCard]s: 2 columns on phones, up to 4 on wide screens.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.minTileWidth = 160});

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minTileWidth).floor().clamp(2, 4);
        const spacing = 10.0;
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final c in children) SizedBox(width: width, height: 132, child: c)],
        );
      },
    );
  }
}
