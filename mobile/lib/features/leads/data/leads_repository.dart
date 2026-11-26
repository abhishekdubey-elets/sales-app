import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/page_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/json.dart';
import 'lead_models.dart';

final leadsRepositoryProvider = Provider<LeadsRepository>((ref) => LeadsRepository(ref.watch(apiClientProvider)));

/// Query for `GET /leads`.
class LeadQuery {
  const LeadQuery({
    this.q,
    this.status,
    this.priority,
    this.assignedTo,
    this.source,
    this.industry,
    this.favourites = false,
    this.followupDue,
    this.sort,
  });

  final String? q;
  final String? status;
  final String? priority;

  /// A user id, `me`, or `unassigned`.
  final String? assignedTo;
  final String? source;
  final String? industry;
  final bool favourites;
  final String? followupDue;
  final String? sort;

  Map<String, dynamic> toQuery() => {
    'q': q,
    'status': status,
    'priority': priority,
    'assigned_to': assignedTo,
    'source': source,
    'industry': industry,
    if (favourites) 'favourites': true,
    'followup_due': followupDue,
    'sort': sort,
  };

  @override
  bool operator ==(Object other) =>
      other is LeadQuery &&
      other.q == q &&
      other.status == status &&
      other.priority == priority &&
      other.assignedTo == assignedTo &&
      other.source == source &&
      other.industry == industry &&
      other.favourites == favourites &&
      other.followupDue == followupDue &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(q, status, priority, assignedTo, source, industry, favourites, followupDue, sort);
}

class LeadsRepository {
  LeadsRepository(this._api);

  final ApiClient _api;

  Future<PageResult<Lead>> list(LeadQuery query, {int page = 1, int pageSize = 20}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/leads',
      query: {...query.toQuery(), 'page': page, 'page_size': pageSize},
    );
    return PageResult.fromJson(data, Lead.fromJson);
  }

  Future<Lead> get(String id) async => Lead.fromJson(await _api.get<Map<String, dynamic>>('/leads/$id'));

  /// Throws [ApiException] with code `duplicate_lead` and `extra['duplicate_lead_id']` on 409.
  Future<Lead> create(Map<String, dynamic> body) async =>
      Lead.fromJson(await _api.post<Map<String, dynamic>>('/leads', body: compact(body)));

  Future<Lead> update(String id, Map<String, dynamic> body) async =>
      Lead.fromJson(await _api.patch<Map<String, dynamic>>('/leads/$id', body: body));

  Future<void> delete(String id) => _api.delete<dynamic>('/leads/$id');

  Future<DuplicateCheck> checkDuplicate({String? phone, String? email}) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/leads/check-duplicate',
      body: compact({'phone': phone, 'email': email}),
    );
    return DuplicateCheck.fromJson(data);
  }

  /// Exact phone lookup for the dialer; null when no lead has this number.
  Future<Lead?> lookup(String phone) async {
    try {
      return Lead.fromJson(await _api.get<Map<String, dynamic>>('/leads/lookup', query: {'phone': phone}));
    } on ApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  Future<List<TimelineItem>> timeline(String id) async =>
      asList(await _api.get<List<dynamic>>('/leads/$id/timeline'), TimelineItem.fromJson);

  Future<List<UnifiedCall>> calls(String id) async =>
      asList(await _api.get<List<dynamic>>('/leads/$id/calls'), UnifiedCall.fromJson);

  Future<void> setFavourite(String id, bool favourite) =>
      favourite ? _api.post<dynamic>('/leads/$id/favourite') : _api.delete<dynamic>('/leads/$id/favourite');

  Future<Lead> optOut(String id, {String? reason}) async =>
      Lead.fromJson(await _api.post<Map<String, dynamic>>('/leads/$id/opt-out', body: compact({'reason': reason})));

  Future<int> assign(List<String> leadIds, String assigneeId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/leads/assign',
      body: {'lead_ids': leadIds, 'assignee_id': assigneeId},
    );
    return asInt(data['assigned']);
  }

  Future<ImportResult> importFile(Uint8List bytes, String filename, {String? assigneeId, String? source}) async {
    final data = await _api.upload<Map<String, dynamic>>(
      '/leads/import',
      bytes: bytes,
      filename: filename,
      fields: {'assignee_id': assigneeId, 'source': source},
    );
    return ImportResult.fromJson(data);
  }

  Future<String> importTemplate() => _api.getText('/leads/import/template');
}

final leadDetailProvider = FutureProvider.autoDispose.family<Lead, String>(
  (ref, id) => ref.watch(leadsRepositoryProvider).get(id),
);

final leadTimelineProvider = FutureProvider.autoDispose.family<List<TimelineItem>, String>(
  (ref, id) => ref.watch(leadsRepositoryProvider).timeline(id),
);

final leadCallsProvider = FutureProvider.autoDispose.family<List<UnifiedCall>, String>(
  (ref, id) => ref.watch(leadsRepositoryProvider).calls(id),
);
