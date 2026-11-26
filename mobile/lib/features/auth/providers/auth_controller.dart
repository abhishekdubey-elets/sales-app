import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/push/push_service.dart';
import '../data/auth_models.dart';
import '../data/auth_repository.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState._(this.status, {this.user, this.message});

  const AuthState.unknown({String? message}) : this._(AuthStatus.unknown, message: message);
  const AuthState.authenticated(User user) : this._(AuthStatus.authenticated, user: user);
  const AuthState.unauthenticated({String? message}) : this._(AuthStatus.unauthenticated, message: message);

  final AuthStatus status;
  final User? user;

  /// Shown on the login/splash screen (e.g. "Session expired").
  final String? message;

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// The signed-in user, or null. Most screens only render when this is non-null.
final currentUserProvider = Provider<User?>((ref) => ref.watch(authControllerProvider).user);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(restore);
    return const AuthState.unknown();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Restores a saved session on app start.
  Future<void> restore() async {
    state = const AuthState.unknown();
    final tokens = ref.read(tokenStorageProvider);
    await tokens.load();
    if (!tokens.hasSession) {
      state = const AuthState.unauthenticated();
      return;
    }
    try {
      final user = await _repo.me();
      state = AuthState.authenticated(user);
      unawaited(ref.read(pushServiceProvider).register());
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await tokens.clear();
        state = const AuthState.unauthenticated(message: 'Your session has expired. Please sign in again.');
      } else {
        // Server unreachable: keep tokens, let the splash screen offer a retry.
        state = AuthState.unknown(message: e.friendlyMessage);
      }
    }
  }

  /// Throws [ApiException] on failure so the form can show it.
  Future<void> login(String email, String password, {String? portal}) async {
    final pair = await _repo.login(email, password, portal: portal);
    state = AuthState.authenticated(pair.user);
    unawaited(ref.read(pushServiceProvider).register());
  }

  Future<void> logout() async {
    try {
      await _repo.logout();
    } catch (_) {
      // Tokens are cleared locally even if the server call fails.
    }
    state = const AuthState.unauthenticated();
  }

  Future<void> refreshUser() async {
    final user = await _repo.me();
    state = AuthState.authenticated(user);
  }

  void setUser(User user) => state = AuthState.authenticated(user);

  void handleSessionExpired() {
    if (state.status == AuthStatus.unauthenticated) return;
    unawaited(ref.read(tokenStorageProvider).clear());
    state = const AuthState.unauthenticated(message: 'Your session has expired. Please sign in again.');
  }
}
