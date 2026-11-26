import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/network/realtime_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class EletsSalesCallApp extends ConsumerWidget {
  const EletsSalesCallApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the realtime socket alive for the whole signed-in session.
    ref.watch(realtimeServiceProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Elets SalesCall AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Brand spec: white/light UI. The dark theme is kept for a future in-app toggle.
      themeMode: ThemeMode.light,
      routerConfig: router,
    );
  }
}
