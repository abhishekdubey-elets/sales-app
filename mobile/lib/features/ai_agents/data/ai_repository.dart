import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/date_range_filter.dart';
import '../../../core/models/page_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'ai_models.dart';

final aiRepositoryProvider = Provider<AiRepository>((ref) => AiRepository(ref.watch(apiClientProvider)));

class AiCallQuery {
  const AiCallQuery({this.agentId, this.campaignId, this.status, this.interestLevel, this.handoff, this.range});

  final String? agentId;
  final String? campaignId;
  final String? status;
  final String? interestLevel;
  final bool? handoff;
  final DateRangeFilter? range;

  Map<String, dynamic> toQuery() => {
    'agent_id': agentId,
    'campaign_id': campaignId,
    'status': status,
    'interest_level': interestLevel,
    'handoff': handoff,
    ...?range?.toQuery(),
  };

  @override
  bool operator ==(Object other) =>
      other is AiCallQuery &&
      other.agentId == agentId &&
      other.campaignId == campaignId &&
      other.status == status &&
      other.interestLevel == interestLevel &&
      other.handoff == handoff &&
      other.range == range;

  @override
  int get hashCode => Object.hash(agentId, campaignId, status, interestLevel, handoff, range);
}

class AiRepository {
  AiRepository(this._api);

  final ApiClient _api;

  Future<List<AIAgent>> agents() async => asList(await _api.get<List<dynamic>>('/ai/agents'), AIAgent.fromJson);

  Future<List<AIAgentConfig>> templates() async =>
      asList(await _api.get<List<dynamic>>('/ai/agents/templates'), AIAgentConfig.fromJson);

  Future<AIAgent> agent(String id) async => AIAgent.fromJson(await _api.get<Map<String, dynamic>>('/ai/agents/$id'));

  Future<AIAgent> createAgent(AIAgentConfig config) async =>
      AIAgent.fromJson(await _api.post<Map<String, dynamic>>('/ai/agents', body: config.toJson()));

  Future<AIAgent> updateAgent(String id, Map<String, dynamic> body) async =>
      AIAgent.fromJson(await _api.patch<Map<String, dynamic>>('/ai/agents/$id', body: body));

  /// Archives the agent (`is_active=false`).
  Future<void> archiveAgent(String id) => _api.delete<dynamic>('/ai/agents/$id');

  Future<TestReply> testReply(String id, String message, List<Map<String, String>> history) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/ai/agents/$id/test-reply',
      body: {'message': message, 'history': history},
    );
    return TestReply.fromJson(data);
  }

  Future<VoiceStatus> voiceStatus() async =>
      VoiceStatus.fromJson(await _api.get<Map<String, dynamic>>('/ai/voice-status'));

  Future<AIDashboard> dashboard(DateRangeFilter range, {String? agentId, String? campaignId}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/ai/dashboard',
      query: {...range.toQuery(), 'agent_id': agentId, 'campaign_id': campaignId},
    );
    return AIDashboard.fromJson(data);
  }

  Future<PageResult<AICall>> calls(AiCallQuery query, {int page = 1, int pageSize = 20}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/ai/calls',
      query: {...query.toQuery(), 'page': page, 'page_size': pageSize},
    );
    return PageResult.fromJson(data, AICall.fromJson);
  }

  Future<AICallDetail> call(String id) async =>
      AICallDetail.fromJson(await _api.get<Map<String, dynamic>>('/ai/calls/$id'));

  /// Admin test call. Same failure codes as human calls.
  Future<AICall> startTestCall({required String agentId, required String leadId}) async => AICall.fromJson(
    await _api.post<Map<String, dynamic>>('/ai/calls', body: {'agent_id': agentId, 'lead_id': leadId}),
  );

  Future<void> hangup(String id) => _api.post<dynamic>('/ai/calls/$id/hangup');
}

final aiAgentsProvider = FutureProvider.autoDispose<List<AIAgent>>((ref) => ref.watch(aiRepositoryProvider).agents());

final aiAgentProvider = FutureProvider.autoDispose.family<AIAgent, String>(
  (ref, id) => ref.watch(aiRepositoryProvider).agent(id),
);

final voiceStatusProvider = FutureProvider.autoDispose<VoiceStatus>(
  (ref) => ref.watch(aiRepositoryProvider).voiceStatus(),
);

final aiDashboardProvider = FutureProvider.autoDispose<AIDashboard>((ref) {
  final range = ref.watch(aiRangeProvider);
  return ref.watch(aiRepositoryProvider).dashboard(range);
});

final aiCallDetailProvider = FutureProvider.autoDispose.family<AICallDetail, String>(
  (ref, id) => ref.watch(aiRepositoryProvider).call(id),
);
