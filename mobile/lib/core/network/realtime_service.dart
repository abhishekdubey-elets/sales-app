import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../config/env.dart';
import 'api_client.dart';

/// `{"type": "call.status", "data": {...}}`
class RealtimeEvent {
  const RealtimeEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;

  static const callStatus = 'call.status';
  static const callIncoming = 'call.incoming';
  static const aiCallStatus = 'ai_call.status';
  static const campaignProgress = 'campaign.progress';
  static const notification = 'notification';
}

enum RealtimeConnection { disconnected, connecting, connected }

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final service = RealtimeService(
    tokenProvider: () => ref.read(tokenStorageProvider).accessToken,
    refreshTokens: () => ref.read(apiClientProvider).refreshTokens(),
  );
  ref.listen<AuthState>(authControllerProvider, (prev, next) {
    if (next.isAuthenticated) {
      service.start();
    } else {
      service.stop();
    }
  }, fireImmediately: true);
  ref.onDispose(service.dispose);
  return service;
});

/// Latest realtime event; widgets use `ref.listen` on this to react to pushes.
final realtimeEventsProvider = StreamProvider<RealtimeEvent>((ref) {
  return ref.watch(realtimeServiceProvider).events;
});

final realtimeConnectionProvider = StreamProvider<RealtimeConnection>((ref) {
  return ref.watch(realtimeServiceProvider).connection;
});

/// Keeps one authenticated WebSocket open while signed in, reconnecting with
/// exponential backoff (1s → 30s) and a 25s keep-alive ping.
class RealtimeService {
  RealtimeService({required this.tokenProvider, required this.refreshTokens});

  final String? Function() tokenProvider;
  final Future<bool> Function() refreshTokens;

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _connection = StreamController<RealtimeConnection>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _active = false;
  int _attempt = 0;
  DateTime? _openedAt;

  Stream<RealtimeEvent> get events => _events.stream;
  Stream<RealtimeConnection> get connection => _connection.stream;

  void start() {
    if (_active) return;
    _active = true;
    _attempt = 0;
    _connect();
  }

  void stop() {
    _active = false;
    _teardown();
    _emitConnection(RealtimeConnection.disconnected);
  }

  Future<void> _connect() async {
    if (!_active) return;
    final token = tokenProvider();
    if (token == null) return;
    _emitConnection(RealtimeConnection.connecting);
    try {
      final channel = WebSocketChannel.connect(Env.wsUri(token));
      _channel = channel;
      await channel.ready;
      if (!_active) {
        await channel.sink.close();
        return;
      }
      _openedAt = DateTime.now();
      _emitConnection(RealtimeConnection.connected);
      _sub = channel.stream.listen(
        _onMessage,
        onError: (Object _) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _channel?.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('Realtime connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final type = decoded['type']?.toString();
      if (type == null || type == 'pong' || type == 'hello') {
        _attempt = 0;
        return;
      }
      final data = decoded['data'];
      _events.add(RealtimeEvent(type, data is Map ? Map<String, dynamic>.from(data) : const {}));
    } catch (e) {
      debugPrint('Realtime: bad message $e');
    }
  }

  void _scheduleReconnect() {
    // A socket that closes right after opening usually means an expired token.
    final openedAt = _openedAt;
    final closedFast = openedAt == null || DateTime.now().difference(openedAt) < const Duration(seconds: 5);
    _teardown();
    if (!_active) return;
    _emitConnection(RealtimeConnection.disconnected);
    final delay = Duration(seconds: min(30, pow(2, _attempt).toInt()));
    _attempt = min(_attempt + 1, 6);
    _reconnectTimer = Timer(delay, () async {
      if (closedFast) await refreshTokens();
      await _connect();
    });
  }

  void _teardown() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _openedAt = null;
  }

  void _emitConnection(RealtimeConnection c) {
    if (!_connection.isClosed) _connection.add(c);
  }

  void dispose() {
    stop();
    _events.close();
    _connection.close();
  }
}
