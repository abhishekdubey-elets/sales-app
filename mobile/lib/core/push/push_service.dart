import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../config/env.dart';

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref.watch(authRepositoryProvider)));

/// Firebase Cloud Messaging registration. Disabled unless the app is built
/// with `--dart-define=FCM_ENABLED=true` and the Firebase config files exist.
/// In-app delivery does not depend on this: the WebSocket pushes notifications too.
class PushService {
  PushService(this._auth);

  final AuthRepository _auth;
  bool _initialised = false;
  StreamSubscription<String>? _tokenSub;

  Future<void> register() async {
    if (!Env.fcmEnabled) return;
    try {
      if (!_initialised) {
        await Firebase.initializeApp();
        _initialised = true;
      }
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // onRegistered fires with the FCM token after register() and on every token refresh.
      _tokenSub ??= messaging.onRegistered.listen((t) => _auth.registerDeviceToken(t, _platform));
      await messaging.register();
    } catch (e) {
      debugPrint('Push registration skipped: $e');
    }
  }

  String get _platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }
}
