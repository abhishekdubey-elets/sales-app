import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/auth_controller.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Logo(),
              const SizedBox(height: 24),
              if (auth.message == null) ...[
                const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
                const SizedBox(height: 12),
                Text('Restoring your session…', style: theme.textTheme.bodyMedium),
              ] else ...[
                Icon(Icons.cloud_off_outlined, color: theme.colorScheme.error, size: 36),
                const SizedBox(height: 12),
                Text(auth.message!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                      child: const Text('Sign out'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => ref.read(authControllerProvider.notifier).restore(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.headset_mic, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 12),
        Text('Elets SalesCall AI', style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}
