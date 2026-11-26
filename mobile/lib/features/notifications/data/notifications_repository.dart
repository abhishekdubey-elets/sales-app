import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/page_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/realtime_service.dart';
import '../../../core/utils/json.dart';
import '../../auth/providers/auth_controller.dart';
import 'notification_models.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);

class NotificationsRepository {
  NotificationsRepository(this._api);

  final ApiClient _api;

  Future<PageResult<AppNotification>> list({bool unreadOnly = false, int page = 1, int pageSize = 20}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/notifications',
      query: {if (unreadOnly) 'unread_only': true, 'page': page, 'page_size': pageSize},
    );
    return PageResult.fromJson(data, AppNotification.fromJson);
  }

  Future<int> unreadCount() async =>
      asInt((await _api.get<Map<String, dynamic>>('/notifications/unread-count'))['count']);

  Future<void> markRead(String id) => _api.post<dynamic>('/notifications/$id/read');

  Future<void> markAllRead() => _api.post<dynamic>('/notifications/read-all');
}

final unreadCountProvider = AsyncNotifierProvider<UnreadCountNotifier, int>(UnreadCountNotifier.new);

/// Unread badge: fetched from the API and bumped live by `notification` WS events.
class UnreadCountNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return 0;
    final sub = ref.watch(realtimeServiceProvider).events.listen((event) {
      if (event.type == RealtimeEvent.notification) {
        final current = state.value ?? 0;
        state = AsyncData(current + 1);
      }
    });
    ref.onDispose(sub.cancel);
    return ref.read(notificationsRepositoryProvider).unreadCount();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(notificationsRepositoryProvider).unreadCount());
  }

  void decrement() {
    final current = state.value ?? 0;
    if (current > 0) state = AsyncData(current - 1);
  }

  Future<void> markAllRead() async {
    await ref.read(notificationsRepositoryProvider).markAllRead();
    state = const AsyncData(0);
  }
}
