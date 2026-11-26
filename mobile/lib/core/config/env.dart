/// Compile-time configuration, supplied with `--dart-define`.
///
/// ```
/// flutter run --dart-define=API_BASE_URL=https://api.example.com --dart-define=FCM_ENABLED=true
/// ```
class Env {
  Env._();

  /// Backend origin, without the `/api/v1` suffix.
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');

  /// Firebase Cloud Messaging is only initialised when this is true, because it
  /// needs platform config files (google-services.json / GoogleService-Info.plist).
  static const bool fcmEnabled = bool.fromEnvironment('FCM_ENABLED');

  static String get _origin => apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;

  /// REST root, e.g. `http://localhost:8000/api/v1`.
  static String get apiRoot => '$_origin/api/v1';

  /// WebSocket URL for realtime events, derived from [apiBaseUrl].
  static Uri wsUri(String accessToken) {
    final base = Uri.parse(_origin);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return base.replace(scheme: scheme, path: '${base.path}/api/v1/ws', queryParameters: {'token': accessToken});
  }
}
