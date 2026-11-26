import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Access/refresh tokens, kept in the platform keystore and cached in memory.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'elets.access_token';
  static const _refreshKey = 'elets.refresh_token';

  final FlutterSecureStorage _storage;
  String? _access;
  String? _refresh;
  bool _loaded = false;

  String? get accessToken => _access;
  String? get refreshToken => _refresh;
  bool get hasSession => _refresh != null;

  Future<void> load() async {
    if (_loaded) return;
    try {
      _access = await _storage.read(key: _accessKey);
      _refresh = await _storage.read(key: _refreshKey);
    } catch (_) {
      // Corrupt keystore entries (e.g. after a reinstall) — start signed out.
      _access = null;
      _refresh = null;
    }
    _loaded = true;
  }

  Future<void> save({required String accessToken, required String refreshToken}) async {
    _access = accessToken;
    _refresh = refreshToken;
    _loaded = true;
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    try {
      await _storage.delete(key: _accessKey);
      await _storage.delete(key: _refreshKey);
    } catch (_) {}
  }
}
