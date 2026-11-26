import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/date_range_filter.dart';
import '../../../core/models/page_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'analytics_models.dart';

final analyticsRepositoryProvider = Provider<AnalyticsRepository>(
  (ref) => AnalyticsRepository(ref.watch(apiClientProvider)),
);

class AnalyticsRepository {
  AnalyticsRepository(this._api);

  final ApiClient _api;

  Future<DashboardStats> dashboard(DateRangeFilter range) async =>
      DashboardStats.fromJson(await _api.get<Map<String, dynamic>>('/analytics/dashboard', query: range.toQuery()));

  Future<List<LeaderboardRow>> leaderboard(DateRangeFilter range, {String? teamId}) async => asList(
    await _api.get<List<dynamic>>('/analytics/leaderboard', query: {...range.toQuery(), 'team_id': teamId}),
    LeaderboardRow.fromJson,
  );

  Future<List<CallsByDatePoint>> callsByDate(DateRangeFilter range) async => asList(
    await _api.get<List<dynamic>>('/analytics/calls-by-date', query: range.toQuery()),
    CallsByDatePoint.fromJson,
  );

  Future<List<LeaderboardRow>> callsBySalesperson(DateRangeFilter range, {String? teamId}) async => asList(
    await _api.get<List<dynamic>>('/analytics/calls-by-salesperson', query: {...range.toQuery(), 'team_id': teamId}),
    LeaderboardRow.fromJson,
  );

  Future<List<DepartmentRow>> callsByDepartment(DateRangeFilter range) async => asList(
    await _api.get<List<dynamic>>('/analytics/calls-by-department', query: range.toQuery()),
    DepartmentRow.fromJson,
  );

  Future<HumanVsAi> humanVsAi(DateRangeFilter range) async =>
      HumanVsAi.fromJson(await _api.get<Map<String, dynamic>>('/analytics/human-vs-ai', query: range.toQuery()));

  Future<List<AgentPerformance>> agents(DateRangeFilter range) async =>
      asList(await _api.get<List<dynamic>>('/analytics/agents', query: range.toQuery()), AgentPerformance.fromJson);

  Future<List<CampaignPerformance>> campaigns() async =>
      asList(await _api.get<List<dynamic>>('/analytics/campaigns'), CampaignPerformance.fromJson);

  Future<MyStats> me(DateRangeFilter range) async =>
      MyStats.fromJson(await _api.get<Map<String, dynamic>>('/analytics/me', query: range.toQuery()));

  /// [report] calls | ai_calls | leads | leaderboard; [format] csv | xlsx.
  Future<SignedUrl> exportLink({required String report, required String format, required DateRangeFilter range}) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/analytics/export-link',
      body: {'report': report, 'format': format, ...range.toQuery()},
    );
    return SignedUrl.fromJson(data);
  }
}

// Dashboard
final dashboardStatsProvider = FutureProvider.autoDispose<DashboardStats>(
  (ref) => ref.watch(analyticsRepositoryProvider).dashboard(ref.watch(dashboardRangeProvider)),
);
final dashboardLeaderboardProvider = FutureProvider.autoDispose<List<LeaderboardRow>>(
  (ref) => ref.watch(analyticsRepositoryProvider).leaderboard(ref.watch(dashboardRangeProvider)),
);
final dashboardCallsByDateProvider = FutureProvider.autoDispose<List<CallsByDatePoint>>(
  (ref) => ref.watch(analyticsRepositoryProvider).callsByDate(ref.watch(dashboardRangeProvider)),
);
final dashboardHumanVsAiProvider = FutureProvider.autoDispose<HumanVsAi>(
  (ref) => ref.watch(analyticsRepositoryProvider).humanVsAi(ref.watch(dashboardRangeProvider)),
);

/// Personal stats always use their own preset-based periods (today/week/month).
final myStatsProvider = FutureProvider.autoDispose<MyStats>(
  (ref) => ref.watch(analyticsRepositoryProvider).me(ref.watch(myStatsRangeProvider)),
);

// Analytics screen
final analyticsHumanVsAiProvider = FutureProvider.autoDispose<HumanVsAi>(
  (ref) => ref.watch(analyticsRepositoryProvider).humanVsAi(ref.watch(analyticsRangeProvider)),
);
final analyticsCallsByDateProvider = FutureProvider.autoDispose<List<CallsByDatePoint>>(
  (ref) => ref.watch(analyticsRepositoryProvider).callsByDate(ref.watch(analyticsRangeProvider)),
);
final analyticsBySalespersonProvider = FutureProvider.autoDispose<List<LeaderboardRow>>(
  (ref) => ref.watch(analyticsRepositoryProvider).callsBySalesperson(ref.watch(analyticsRangeProvider)),
);
final analyticsByDepartmentProvider = FutureProvider.autoDispose<List<DepartmentRow>>(
  (ref) => ref.watch(analyticsRepositoryProvider).callsByDepartment(ref.watch(analyticsRangeProvider)),
);
final analyticsAgentsProvider = FutureProvider.autoDispose<List<AgentPerformance>>(
  (ref) => ref.watch(analyticsRepositoryProvider).agents(ref.watch(analyticsRangeProvider)),
);
final analyticsCampaignsProvider = FutureProvider.autoDispose<List<CampaignPerformance>>(
  (ref) => ref.watch(analyticsRepositoryProvider).campaigns(),
);
