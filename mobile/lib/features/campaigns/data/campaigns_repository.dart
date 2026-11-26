import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/page_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../../leads/data/lead_models.dart';
import 'campaign_models.dart';

final campaignsRepositoryProvider = Provider<CampaignsRepository>(
  (ref) => CampaignsRepository(ref.watch(apiClientProvider)),
);

class CampaignDraft {
  const CampaignDraft({
    required this.name,
    required this.agentId,
    this.description,
    this.schedule = const CampaignSchedule(),
    this.maxAttempts = 3,
    this.retryDelayMinutes = 60,
    this.maxConcurrentCalls = 2,
    this.callsPerMinute = 4,
  });

  final String name;
  final String? description;
  final String agentId;
  final CampaignSchedule schedule;
  final int maxAttempts;
  final int retryDelayMinutes;
  final int maxConcurrentCalls;
  final int callsPerMinute;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'agent_id': agentId,
    'schedule': schedule.toJson(),
    'max_attempts': maxAttempts,
    'retry_delay_minutes': retryDelayMinutes,
    'max_concurrent_calls': maxConcurrentCalls,
    'calls_per_minute': callsPerMinute,
  };
}

class AddLeadsResult {
  const AddLeadsResult({required this.added, required this.skipped});

  factory AddLeadsResult.fromJson(Map<String, dynamic> j) =>
      AddLeadsResult(added: asInt(j['added']), skipped: asInt(j['skipped']));

  final int added;
  final int skipped;
}

class CampaignsRepository {
  CampaignsRepository(this._api);

  final ApiClient _api;

  Future<List<Campaign>> list({String? status}) async =>
      asList(await _api.get<List<dynamic>>('/ai/campaigns', query: {'status': status}), Campaign.fromJson);

  Future<Campaign> get(String id) async => Campaign.fromJson(await _api.get<Map<String, dynamic>>('/ai/campaigns/$id'));

  Future<Campaign> create(CampaignDraft draft) async =>
      Campaign.fromJson(await _api.post<Map<String, dynamic>>('/ai/campaigns', body: draft.toJson()));

  Future<Campaign> update(String id, Map<String, dynamic> body) async =>
      Campaign.fromJson(await _api.patch<Map<String, dynamic>>('/ai/campaigns/$id', body: body));

  Future<AddLeadsResult> addLeadsByIds(String id, List<String> leadIds) async => AddLeadsResult.fromJson(
    await _api.post<Map<String, dynamic>>('/ai/campaigns/$id/leads', body: {'lead_ids': leadIds}),
  );

  Future<AddLeadsResult> addLeadsByFilter(String id, Map<String, dynamic> filter) async => AddLeadsResult.fromJson(
    await _api.post<Map<String, dynamic>>('/ai/campaigns/$id/leads', body: {'filter': compact(filter)}),
  );

  Future<ImportResult> importLeads(String id, Uint8List bytes, String filename) async => ImportResult.fromJson(
    await _api.upload<Map<String, dynamic>>('/ai/campaigns/$id/leads/import', bytes: bytes, filename: filename),
  );

  Future<PageResult<CampaignLead>> leads(String id, {String? status, int page = 1, int pageSize = 20}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/ai/campaigns/$id/leads',
      query: {'status': status, 'page': page, 'page_size': pageSize},
    );
    return PageResult.fromJson(data, CampaignLead.fromJson);
  }

  Future<PageResult<CampaignLog>> logs(String id, {int page = 1, int pageSize = 30}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/ai/campaigns/$id/logs',
      query: {'page': page, 'page_size': pageSize},
    );
    return PageResult.fromJson(data, CampaignLog.fromJson);
  }

  /// [action] is start | pause | resume | stop.
  Future<Campaign> control(String id, String action) async =>
      Campaign.fromJson(await _api.post<Map<String, dynamic>>('/ai/campaigns/$id/$action'));
}

final campaignsProvider = FutureProvider.autoDispose<List<Campaign>>(
  (ref) => ref.watch(campaignsRepositoryProvider).list(),
);

final campaignDetailProvider = FutureProvider.autoDispose.family<Campaign, String>(
  (ref, id) => ref.watch(campaignsRepositoryProvider).get(id),
);
