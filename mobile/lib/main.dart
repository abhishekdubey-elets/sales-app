import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      // Screens offer an explicit Retry button; don't silently re-fire failing requests.
      retry: (_, _) => null,
      child: const EletsSalesCallApp(),
    ),
  );
}
