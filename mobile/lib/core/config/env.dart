import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App configuration.
///
/// `API_BASE_URL` (a `--dart-define`) is the default server. Users can point the
/// installed app at another server from the login screen; that choice is saved on
/// the device and wins over the build-time default.
///
/// ```
/// flutter build apk --dart-define=API_BASE_URL=https://api.example.com --dart-define=FCM_ENABLED=true
/// ```
class Env {
  Env._();

  static const String defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// Firebase Cloud Messaging is only initialised when this is true, because it
  /// needs platform config files (google-services.json / GoogleService-Info.plist).
  static const bool fcmEnabled = bool.fromEnvironment('FCM_ENABLED');

  static const _storageKey = 'elets.server_url';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static String? _savedBaseUrl;

  /// Backend origin, without the `/api/v1` suffix.
  static String get apiBaseUrl => _savedBaseUrl ?? defaultApiBaseUrl;

  static bool get isCustomServer => _savedBaseUrl != null;

  /// Loads the server chosen on this device, if any. Call once before `runApp`.
  static Future<void> load() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      _savedBaseUrl = saved == null ? null : normalizeServerUrl(saved);
    } catch (_) {
      _savedBaseUrl = null;
    }
  }

  /// Saves [url] as this device's server. `null` restores the build-time default.
  static Future<void> setServer(String? url) async {
    final normalized = url == null ? null : normalizeServerUrl(url);
    _savedBaseUrl = normalized == normalizeServerUrl(defaultApiBaseUrl) ? null : normalized;
    try {
      if (_savedBaseUrl == null) {
        await _storage.delete(key: _storageKey);
      } else {
        await _storage.write(key: _storageKey, value: _savedBaseUrl);
      }
    } catch (_) {
      // Keep the in-memory value for this run even if the keystore is unavailable.
    }
  }

  /// `192.168.1.5:8000` → `http://192.168.1.5:8000`; drops a trailing `/` or `/api/v1`.
  /// Returns null when the text isn't a usable http(s) URL.
  static String? normalizeServerUrl(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'http://$text';
    var uri = Uri.tryParse(text);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) return null;
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith('/api/v1')) path = path.substring(0, path.length - '/api/v1'.length);
    uri = uri.replace(path: path, query: null, fragment: null);
    final out = uri.toString();
    return out.endsWith('?') || out.endsWith('#') ? out.substring(0, out.length - 1) : out;
  }

  static String get _origin =>
      apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;

  /// REST root, e.g. `http://localhost:8000/api/v1`.
  static String get apiRoot => '$_origin/api/v1';

  /// WebSocket URL for realtime events, derived from [apiBaseUrl].
  static Uri wsUri(String accessToken) {
    final base = Uri.parse(_origin);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return base.replace(scheme: scheme, path: '${base.path}/api/v1/ws', queryParameters: {'token': accessToken});
  }
}
