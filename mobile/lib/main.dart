import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.load(); // server address chosen on this device, if any
  runApp(
    ProviderScope(
      // Screens offer an explicit Retry button; don't silently re-fire failing requests.
      retry: (_, _) => null,
      child: const EletsSalesCallApp(),
    ),
  );
}
