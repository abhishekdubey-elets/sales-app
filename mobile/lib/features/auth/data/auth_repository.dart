import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'auth_models.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(apiClientProvider)));

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  static String get _deviceName {
    if (kIsWeb) return 'Web browser';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android app',
      TargetPlatform.iOS => 'iOS app',
      _ => 'Elets SalesCall app',
    };
  }

  Future<TokenPair> login(String email, String password) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/auth/login',
      body: {'email': email.trim(), 'password': password, 'device_name': _deviceName},
    );
    final pair = TokenPair.fromJson(data);
    await _api.tokens.save(accessToken: pair.accessToken, refreshToken: pair.refreshToken);
    return pair;
  }

  Future<User> me() async => User.fromJson(await _api.get<Map<String, dynamic>>('/auth/me'));

  Future<void> logout() async {
    final refresh = _api.tokens.refreshToken;
    try {
      if (refresh != null) await _api.post<dynamic>('/auth/logout', body: {'refresh_token': refresh});
    } finally {
      await _api.tokens.clear();
    }
  }

  Future<void> changePassword(String current, String next) =>
      _api.post<dynamic>('/auth/change-password', body: {'current_password': current, 'new_password': next});

  Future<List<UserSession>> sessions() async {
    final data = await _api.get<List<dynamic>>('/auth/sessions');
    return asList(data, UserSession.fromJson);
  }

  Future<void> revokeSession(String id) => _api.delete<dynamic>('/auth/sessions/$id');

  Future<User> updateMe({String? fullName, String? phone, String? callingNumber}) async {
    final data = await _api.patch<Map<String, dynamic>>(
      '/users/me',
      body: {'full_name': ?fullName, 'phone': ?phone, 'calling_number': ?callingNumber},
    );
    return User.fromJson(data);
  }

  Future<void> registerDeviceToken(String token, String platform) =>
      _api.post<dynamic>('/users/me/device-tokens', body: {'token': token, 'platform': platform});
}
