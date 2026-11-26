import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../config/env.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    tokens: ref.watch(tokenStorageProvider),
    // Read lazily: the auth controller itself depends on the API client.
    onSessionExpired: () => ref.read(authControllerProvider.notifier).handleSessionExpired(),
  );
  ref.onDispose(client.close);
  return client;
});

/// Thin wrapper over Dio: JSON in/out, bearer auth with one refresh-and-retry on
/// 401, and every failure converted to [ApiException].
class ApiClient {
  ApiClient({required this.tokens, required this.onSessionExpired, Dio? dio})
    : _dio = dio ?? Dio(_options()),
      _refreshDio = Dio(_options()) {
    _dio.interceptors.add(QueuedInterceptorsWrapper(onRequest: _onRequest, onError: _onError));
  }

  static BaseOptions _options() => BaseOptions(
    baseUrl: Env.apiRoot,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 45),
    sendTimeout: const Duration(seconds: 60),
    headers: {'Accept': 'application/json'},
  );

  final TokenStorage tokens;
  final void Function() onSessionExpired;
  final Dio _dio;
  final Dio _refreshDio;
  Completer<bool>? _refreshing;

  static const _noAuthPaths = ['/auth/login', '/auth/refresh'];

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // The server can be changed at runtime from the login screen.
    options.baseUrl = Env.apiRoot;
    final token = tokens.accessToken;
    if (token != null && !_noAuthPaths.contains(options.path)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    final shouldRefresh =
        err.response?.statusCode == 401 &&
        !_noAuthPaths.contains(req.path) &&
        req.extra['retried'] != true &&
        tokens.refreshToken != null;
    if (!shouldRefresh) return handler.next(err);

    final ok = await refreshTokens();
    if (!ok) {
      onSessionExpired();
      return handler.next(err);
    }
    try {
      req.extra['retried'] = true;
      req.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      final response = await _dio.fetch<dynamic>(req);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Rotates the refresh token. Concurrent callers share one in-flight refresh.
  Future<bool> refreshTokens() async {
    final pending = _refreshing;
    if (pending != null) return pending.future;
    final completer = Completer<bool>();
    _refreshing = completer;
    try {
      final refresh = tokens.refreshToken;
      if (refresh == null) {
        completer.complete(false);
      } else {
        _refreshDio.options.baseUrl = Env.apiRoot;
        final res = await _refreshDio.post<dynamic>('/auth/refresh', data: {'refresh_token': refresh});
        final data = res.data;
        if (data is Map && data['access_token'] != null && data['refresh_token'] != null) {
          await tokens.save(
            accessToken: data['access_token'].toString(),
            refreshToken: data['refresh_token'].toString(),
          );
          completer.complete(true);
        } else {
          completer.complete(false);
        }
      }
    } catch (_) {
      completer.complete(false);
    } finally {
      _refreshing = null;
    }
    return completer.future;
  }

  Future<T> _wrap<T>(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      return res.data as T;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _wrap<T>(() => _dio.get<dynamic>(path, queryParameters: _clean(query)));

  Future<T> post<T>(String path, {Object? body, Map<String, dynamic>? query}) =>
      _wrap<T>(() => _dio.post<dynamic>(path, data: body, queryParameters: _clean(query)));

  Future<T> patch<T>(String path, {Object? body}) => _wrap<T>(() => _dio.patch<dynamic>(path, data: body));

  Future<T> delete<T>(String path) => _wrap<T>(() => _dio.delete<dynamic>(path));

  /// Multipart upload from bytes (works on web, where file paths don't exist).
  Future<T> upload<T>(
    String path, {
    required Uint8List bytes,
    required String filename,
    Map<String, dynamic> fields = const {},
  }) {
    final form = FormData.fromMap({
      ..._clean(fields) ?? {},
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    return _wrap<T>(
      () => _dio.post<dynamic>(
        path,
        data: form,
        options: Options(sendTimeout: const Duration(minutes: 3), receiveTimeout: const Duration(minutes: 3)),
      ),
    );
  }

  /// Fetches a text resource (e.g. the CSV import template).
  Future<String> getText(String path) =>
      _wrap<String>(() => _dio.get<dynamic>(path, options: Options(responseType: ResponseType.plain)));

  Map<String, dynamic>? _clean(Map<String, dynamic>? m) {
    if (m == null) return null;
    final out = <String, dynamic>{};
    m.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.isEmpty) return;
      out[k] = v is bool ? v.toString() : v;
    });
    return out;
  }

  void close() {
    _dio.close(force: true);
    _refreshDio.close(force: true);
  }
}
