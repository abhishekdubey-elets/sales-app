import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/page_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'followup_models.dart';

final followupsRepositoryProvider = Provider<FollowupsRepository>(
  (ref) => FollowupsRepository(ref.watch(apiClientProvider)),
);

class FollowupsRepository {
  FollowupsRepository(this._api);

  final ApiClient _api;

  /// [due] is `overdue`, `today` or `upcoming`.
  Future<PageResult<Followup>> list({
    String? status,
    String? due,
    String? assignedTo,
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/followups',
      query: {'status': status, 'due': due, 'assigned_to': assignedTo, 'page': page, 'page_size': pageSize},
    );
    return PageResult.fromJson(data, Followup.fromJson);
  }

  Future<Followup> create({required String leadId, required DateTime dueAt, String? note, String? assignedToId}) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/followups',
      body: compact({'lead_id': leadId, 'due_at': dateToJson(dueAt), 'note': note, 'assigned_to_id': assignedToId}),
    );
    return Followup.fromJson(data);
  }

  Future<Followup> update(String id, {String? status, DateTime? dueAt, String? note}) async {
    final data = await _api.patch<Map<String, dynamic>>(
      '/followups/$id',
      body: compact({'status': status, 'due_at': dateToJson(dueAt), 'note': note}),
    );
    return Followup.fromJson(data);
  }
}

/// Today's and overdue pending follow-ups for the dashboard.
final dueFollowupsProvider = FutureProvider.autoDispose<List<Followup>>((ref) async {
  final repo = ref.watch(followupsRepositoryProvider);
  final results = await Future.wait([
    repo.list(status: 'pending', due: 'overdue', pageSize: 10),
    repo.list(status: 'pending', due: 'today', pageSize: 10),
  ]);
  return [...results[0].items, ...results[1].items];
});
