import 'package:flutter/material.dart';

import '../network/api_exception.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.icon = Icons.inbox_outlined, this.action});

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNetwork = error is ApiException && (error as ApiException).isNetwork;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isNetwork ? Icons.cloud_off_outlined : Icons.error_outline,
          size: compact ? 24 : 40,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 10),
        Text(
          isNetwork ? 'You\'re offline or the server is unreachable' : 'Something went wrong',
          style: compact ? theme.textTheme.titleSmall : theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          errorMessage(error),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ],
      ],
    );
    return Center(
      child: Padding(padding: EdgeInsets.all(compact ? 12 : 32), child: content),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(message!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

/// Placeholder rows shown while a list loads for the first time.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6, this.itemHeight = 64});

  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 12, width: double.infinity, color: color),
                const SizedBox(height: 8),
                FractionallySizedBox(widthFactor: 0.6, child: Container(height: 10, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
