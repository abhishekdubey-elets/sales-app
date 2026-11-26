import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/page_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../../auth/data/auth_models.dart';
import 'team_models.dart';

final teamRepositoryProvider = Provider<TeamRepository>((ref) => TeamRepository(ref.watch(apiClientProvider)));

class TeamRepository {
  TeamRepository(this._api);

  final ApiClient _api;

  Future<PageResult<User>> users({
    String? q,
    String? role,
    String? teamId,
    bool? isActive,
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/users',
      query: {'q': q, 'role': role, 'team_id': teamId, 'is_active': isActive, 'page': page, 'page_size': pageSize},
    );
    return PageResult.fromJson(data, User.fromJson);
  }

  Future<User> user(String id) async => User.fromJson(await _api.get<Map<String, dynamic>>('/users/$id'));

  Future<User> createUser(Map<String, dynamic> body) async =>
      User.fromJson(await _api.post<Map<String, dynamic>>('/users', body: compact(body)));

  Future<User> updateUser(String id, Map<String, dynamic> body) async =>
      User.fromJson(await _api.patch<Map<String, dynamic>>('/users/$id', body: body));

  Future<List<Team>> teams() async => asList(await _api.get<List<dynamic>>('/teams'), Team.fromJson);

  Future<Team> createTeam({required String name, String? department, String? managerId}) async => Team.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/teams',
      body: compact({'name': name, 'department': department, 'manager_id': managerId}),
    ),
  );

  Future<Team> updateTeam(String id, Map<String, dynamic> body) async =>
      Team.fromJson(await _api.patch<Map<String, dynamic>>('/teams/$id', body: body));
}

final teamsProvider = FutureProvider.autoDispose<List<Team>>((ref) => ref.watch(teamRepositoryProvider).teams());

/// Active users the current user may assign leads to (backend scopes managers to their team).
final assignableUsersProvider = FutureProvider.autoDispose<List<User>>((ref) async {
  final page = await ref.watch(teamRepositoryProvider).users(isActive: true, pageSize: 100);
  return page.items;
});

final userDetailProvider = FutureProvider.autoDispose.family<User, String>(
  (ref, id) => ref.watch(teamRepositoryProvider).user(id),
);
