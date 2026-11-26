import '../../../core/utils/json.dart';
import '../../campaigns/data/campaign_models.dart';

class DashboardStats {
  const DashboardStats({
    this.scope = 'personal',
    this.totalLeads = 0,
    this.totalCalls = 0,
    this.successfulCalls = 0,
    this.missedCalls = 0,
    this.connectedCalls = 0,
    this.notConnected = 0,
    this.totalDurationSeconds = 0,
    this.pendingFollowups = 0,
    this.leadsConverted = 0,
    this.aiCalls = 0,
    this.aiSuccessfulConversations = 0,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> j) => DashboardStats(
    scope: asString(j['scope'], 'personal'),
    totalLeads: asInt(j['total_leads']),
    totalCalls: asInt(j['total_calls']),
    successfulCalls: asInt(j['successful_calls']),
    missedCalls: asInt(j['missed_calls']),
    connectedCalls: asInt(j['connected_calls']),
    notConnected: asInt(j['not_connected']),
    totalDurationSeconds: asInt(j['total_duration_seconds']),
    pendingFollowups: asInt(j['pending_followups']),
    leadsConverted: asInt(j['leads_converted']),
    aiCalls: asInt(j['ai_calls']),
    aiSuccessfulConversations: asInt(j['ai_successful_conversations']),
  );

  /// personal | team | organization
  final String scope;
  final int totalLeads;
  final int totalCalls;
  final int successfulCalls;
  final int missedCalls;
  final int connectedCalls;
  final int notConnected;
  final int totalDurationSeconds;
  final int pendingFollowups;
  final int leadsConverted;
  final int aiCalls;
  final int aiSuccessfulConversations;
}

class LeaderboardRow {
  const LeaderboardRow({
    required this.userId,
    required this.name,
    this.teamName,
    this.calls = 0,
    this.connected = 0,
    this.durationSeconds = 0,
    this.conversions = 0,
  });

  factory LeaderboardRow.fromJson(Map<String, dynamic> j) => LeaderboardRow(
    userId: asString(j['user_id']),
    name: asString(j['name']),
    teamName: asStringOrNull(j['team_name']),
    calls: asInt(j['calls']),
    connected: asInt(j['connected']),
    durationSeconds: asInt(j['duration_seconds']),
    conversions: asInt(j['conversions']),
  );

  final String userId;
  final String name;
  final String? teamName;
  final int calls;
  final int connected;
  final int durationSeconds;
  final int conversions;
}

class CallsByDatePoint {
  const CallsByDatePoint({
    required this.date,
    this.human = 0,
    this.ai = 0,
    this.humanConnected = 0,
    this.aiConnected = 0,
  });

  factory CallsByDatePoint.fromJson(Map<String, dynamic> j) => CallsByDatePoint(
    date: parseDate(j['date']) ?? DateTime.now(),
    human: asInt(j['human']),
    ai: asInt(j['ai']),
    humanConnected: asInt(j['human_connected']),
    aiConnected: asInt(j['ai_connected']),
  );

  final DateTime date;
  final int human;
  final int ai;
  final int humanConnected;
  final int aiConnected;
}

class DepartmentRow {
  const DepartmentRow({
    required this.department,
    this.calls = 0,
    this.connected = 0,
    this.durationSeconds = 0,
    this.conversions = 0,
  });

  factory DepartmentRow.fromJson(Map<String, dynamic> j) => DepartmentRow(
    department: asString(j['department'], 'Unassigned'),
    calls: asInt(j['calls']),
    connected: asInt(j['connected']),
    durationSeconds: asInt(j['duration_seconds']),
    conversions: asInt(j['conversions']),
  );

  final String department;
  final int calls;
  final int connected;
  final int durationSeconds;
  final int conversions;
}

class ChannelStats {
  const ChannelStats({
    this.calls = 0,
    this.connected = 0,
    this.avgDurationSeconds = 0,
    this.interested = 0,
    this.converted = 0,
    this.qualified = 0,
  });

  factory ChannelStats.fromJson(Map<String, dynamic> j) => ChannelStats(
    calls: asInt(j['calls']),
    connected: asInt(j['connected']),
    avgDurationSeconds: asInt(j['avg_duration_seconds']),
    interested: asInt(j['interested']),
    converted: asInt(j['converted']),
    qualified: asInt(j['qualified']),
  );

  final int calls;
  final int connected;
  final int avgDurationSeconds;
  final int interested;
  final int converted;
  final int qualified;
}

class HumanVsAi {
  const HumanVsAi({required this.human, required this.ai});

  factory HumanVsAi.fromJson(Map<String, dynamic> j) =>
      HumanVsAi(human: ChannelStats.fromJson(asMap(j['human'])), ai: ChannelStats.fromJson(asMap(j['ai'])));

  final ChannelStats human;
  final ChannelStats ai;
}

class AgentPerformance {
  const AgentPerformance({
    required this.agentId,
    required this.agentName,
    this.calls = 0,
    this.connected = 0,
    this.successful = 0,
    this.qualified = 0,
    this.avgDurationSeconds = 0,
    this.handoffs = 0,
  });

  factory AgentPerformance.fromJson(Map<String, dynamic> j) => AgentPerformance(
    agentId: asString(j['agent_id']),
    agentName: asString(j['agent_name']),
    calls: asInt(j['calls']),
    connected: asInt(j['connected']),
    successful: asInt(j['successful']),
    qualified: asInt(j['qualified']),
    avgDurationSeconds: asInt(j['avg_duration_seconds']),
    handoffs: asInt(j['handoffs']),
  );

  final String agentId;
  final String agentName;
  final int calls;
  final int connected;
  final int successful;
  final int qualified;
  final int avgDurationSeconds;
  final int handoffs;
}

class CampaignPerformance {
  const CampaignPerformance({required this.campaignId, required this.name, required this.status, required this.stats});

  factory CampaignPerformance.fromJson(Map<String, dynamic> j) => CampaignPerformance(
    campaignId: asString(j['campaign_id']),
    name: asString(j['name']),
    status: asString(j['status']),
    stats: CampaignStats.fromJson(asMap(j['stats'])),
  );

  final String campaignId;
  final String name;
  final String status;
  final CampaignStats stats;
}

class MyStats {
  const MyStats({
    this.callsToday = 0,
    this.callsThisWeek = 0,
    this.callsThisMonth = 0,
    this.connected = 0,
    this.missed = 0,
    this.avgDurationSeconds = 0,
    this.interested = 0,
    this.converted = 0,
    this.followupsPending = 0,
  });

  factory MyStats.fromJson(Map<String, dynamic> j) => MyStats(
    callsToday: asInt(j['calls_today']),
    callsThisWeek: asInt(j['calls_this_week']),
    callsThisMonth: asInt(j['calls_this_month']),
    connected: asInt(j['connected']),
    missed: asInt(j['missed']),
    avgDurationSeconds: asInt(j['avg_duration_seconds']),
    interested: asInt(j['interested']),
    converted: asInt(j['converted']),
    followupsPending: asInt(j['followups_pending']),
  );

  final int callsToday;
  final int callsThisWeek;
  final int callsThisMonth;
  final int connected;
  final int missed;
  final int avgDurationSeconds;
  final int interested;
  final int converted;
  final int followupsPending;
}
