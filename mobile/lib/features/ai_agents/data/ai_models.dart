import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';

class RetryRules {
  const RetryRules({this.maxAttempts = 3, this.retryDelayMinutes = 60, this.retryOn = const ['busy', 'not_answered']});

  factory RetryRules.fromJson(Map<String, dynamic> j) => RetryRules(
    maxAttempts: asInt(j['max_attempts'], 3),
    retryDelayMinutes: asInt(j['retry_delay_minutes'], 60),
    retryOn: asStringList(j['retry_on']),
  );

  final int maxAttempts;
  final int retryDelayMinutes;

  /// Subset of busy | not_answered | failed.
  final List<String> retryOn;

  RetryRules copyWith({int? maxAttempts, int? retryDelayMinutes, List<String>? retryOn}) => RetryRules(
    maxAttempts: maxAttempts ?? this.maxAttempts,
    retryDelayMinutes: retryDelayMinutes ?? this.retryDelayMinutes,
    retryOn: retryOn ?? this.retryOn,
  );

  Map<String, dynamic> toJson() => {
    'max_attempts': maxAttempts,
    'retry_delay_minutes': retryDelayMinutes,
    'retry_on': retryOn,
  };
}

/// Editable agent configuration (`AIAgentCreate`).
class AIAgentConfig {
  const AIAgentConfig({
    this.name = '',
    this.description = '',
    this.personality = '',
    this.language = AgentLanguage.englishIndia,
    this.voiceId = '',
    this.speakingSpeed = 1.0,
    this.systemPrompt = '',
    this.knowledgeBase = '',
    this.objectives = const [],
    this.greeting = '',
    this.maxCallDurationSeconds = 300,
    this.retryRules = const RetryRules(),
    this.handoffConditions = const [],
    this.recordingEnabled = true,
  });

  factory AIAgentConfig.fromJson(Map<String, dynamic> j) => AIAgentConfig(
    name: asString(j['name']),
    description: asString(j['description']),
    personality: asString(j['personality']),
    language: AgentLanguage.fromValue(j['language']),
    voiceId: asString(j['voice_id']),
    speakingSpeed: asDouble(j['speaking_speed'], 1.0),
    systemPrompt: asString(j['system_prompt']),
    knowledgeBase: asString(j['knowledge_base']),
    objectives: asStringList(j['objectives']),
    greeting: asString(j['greeting']),
    maxCallDurationSeconds: asInt(j['max_call_duration_seconds'], 300),
    retryRules: RetryRules.fromJson(asMap(j['retry_rules'])),
    handoffConditions: asStringList(j['handoff_conditions']),
    recordingEnabled: asBool(j['recording_enabled'], true),
  );

  final String name;
  final String description;
  final String personality;
  final AgentLanguage language;
  final String voiceId;
  final double speakingSpeed;
  final String systemPrompt;
  final String knowledgeBase;
  final List<String> objectives;
  final String greeting;
  final int maxCallDurationSeconds;
  final RetryRules retryRules;
  final List<String> handoffConditions;
  final bool recordingEnabled;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'personality': personality,
    'language': language.value,
    'voice_id': voiceId,
    'speaking_speed': speakingSpeed,
    'system_prompt': systemPrompt,
    'knowledge_base': knowledgeBase,
    'objectives': objectives,
    'greeting': greeting,
    'max_call_duration_seconds': maxCallDurationSeconds,
    'retry_rules': retryRules.toJson(),
    'handoff_conditions': handoffConditions,
    'recording_enabled': recordingEnabled,
  };
}

class AIAgent {
  const AIAgent({
    required this.id,
    required this.config,
    this.isActive = true,
    this.createdByName,
    this.createdAt,
    this.updatedAt,
    this.totalCalls = 0,
    this.successfulConversations = 0,
  });

  factory AIAgent.fromJson(Map<String, dynamic> j) => AIAgent(
    id: asString(j['id']),
    config: AIAgentConfig.fromJson(j),
    isActive: asBool(j['is_active'], true),
    createdByName: asStringOrNull(j['created_by_name']),
    createdAt: parseDate(j['created_at']),
    updatedAt: parseDate(j['updated_at']),
    totalCalls: asInt(j['total_calls']),
    successfulConversations: asInt(j['successful_conversations']),
  );

  final String id;
  final AIAgentConfig config;
  final bool isActive;
  final String? createdByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int totalCalls;
  final int successfulConversations;

  String get name => config.name;
}

class AIDashboard {
  const AIDashboard({
    this.totalCalls = 0,
    this.inProgress = 0,
    this.completed = 0,
    this.successfulConversations = 0,
    this.qualified = 0,
    this.interested = 0,
    this.followupsRequired = 0,
    this.avgDurationSeconds = 0,
    this.handoffs = 0,
  });

  factory AIDashboard.fromJson(Map<String, dynamic> j) => AIDashboard(
    totalCalls: asInt(j['total_calls']),
    inProgress: asInt(j['in_progress']),
    completed: asInt(j['completed']),
    successfulConversations: asInt(j['successful_conversations']),
    qualified: asInt(j['qualified']),
    interested: asInt(j['interested']),
    followupsRequired: asInt(j['followups_required']),
    avgDurationSeconds: asInt(j['avg_duration_seconds']),
    handoffs: asInt(j['handoffs']),
  );

  final int totalCalls;
  final int inProgress;
  final int completed;
  final int successfulConversations;
  final int qualified;
  final int interested;
  final int followupsRequired;
  final int avgDurationSeconds;
  final int handoffs;
}

class AICall {
  const AICall({
    required this.id,
    required this.status,
    this.agentId,
    this.agentName,
    this.campaignId,
    this.campaignName,
    this.leadId,
    this.leadName,
    this.phoneMasked,
    this.provider,
    this.providerCallId,
    this.attempt = 1,
    this.startedAt,
    this.answeredAt,
    this.endedAt,
    this.durationSeconds = 0,
    this.interestLevel,
    this.qualificationScore,
    this.handoffRequested = false,
    this.summary,
    this.failureReason,
    this.createdAt,
  });

  factory AICall.fromJson(Map<String, dynamic> j) => AICall(
    id: asString(j['id']),
    agentId: asStringOrNull(j['agent_id']),
    agentName: asStringOrNull(j['agent_name']),
    campaignId: asStringOrNull(j['campaign_id']),
    campaignName: asStringOrNull(j['campaign_name']),
    leadId: asStringOrNull(j['lead_id']),
    leadName: asStringOrNull(j['lead_name']),
    phoneMasked: asStringOrNull(j['phone_masked']),
    provider: asStringOrNull(j['provider']),
    providerCallId: asStringOrNull(j['provider_call_id']),
    status: CallStatus.fromValue(j['status']),
    attempt: asInt(j['attempt'], 1),
    startedAt: parseDate(j['started_at']),
    answeredAt: parseDate(j['answered_at']),
    endedAt: parseDate(j['ended_at']),
    durationSeconds: asInt(j['duration_seconds']),
    interestLevel: InterestLevel.fromValueOrNull(j['interest_level']),
    qualificationScore: asIntOrNull(j['qualification_score']),
    handoffRequested: asBool(j['handoff_requested']),
    summary: asStringOrNull(j['summary']),
    failureReason: asStringOrNull(j['failure_reason']),
    createdAt: parseDate(j['created_at']),
  );

  final String id;
  final String? agentId;
  final String? agentName;
  final String? campaignId;
  final String? campaignName;
  final String? leadId;
  final String? leadName;
  final String? phoneMasked;
  final String? provider;
  final String? providerCallId;
  final CallStatus status;
  final int attempt;
  final DateTime? startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final InterestLevel? interestLevel;
  final int? qualificationScore;
  final bool handoffRequested;
  final String? summary;
  final String? failureReason;
  final DateTime? createdAt;
}

class CallIntelligence {
  const CallIntelligence({
    this.summary = '',
    this.customerRequirements = const [],
    this.interestLevel,
    this.budgetInformation,
    this.decisionMakerInformation,
    this.nextAction,
    this.followupRecommendation,
    this.followupDate,
    this.qualificationScore = 0,
    this.sentiment,
    this.leadStatusSuggestion,
  });

  factory CallIntelligence.fromJson(Map<String, dynamic> j) => CallIntelligence(
    summary: asString(j['summary']),
    customerRequirements: asStringList(j['customer_requirements']),
    interestLevel: InterestLevel.fromValueOrNull(j['interest_level']),
    budgetInformation: asStringOrNull(j['budget_information']),
    decisionMakerInformation: asStringOrNull(j['decision_maker_information']),
    nextAction: asStringOrNull(j['next_action']),
    followupRecommendation: asStringOrNull(j['followup_recommendation']),
    followupDate: parseDate(j['followup_date']),
    qualificationScore: asInt(j['qualification_score']),
    sentiment: asStringOrNull(j['sentiment']),
    leadStatusSuggestion: LeadStatus.fromValueOrNull(j['lead_status_suggestion']),
  );

  final String summary;
  final List<String> customerRequirements;
  final InterestLevel? interestLevel;
  final String? budgetInformation;
  final String? decisionMakerInformation;
  final String? nextAction;
  final String? followupRecommendation;
  final DateTime? followupDate;
  final int qualificationScore;
  final String? sentiment;
  final LeadStatus? leadStatusSuggestion;
}

class TranscriptLine {
  const TranscriptLine({required this.speaker, required this.text, this.offsetMs = 0});

  factory TranscriptLine.fromJson(Map<String, dynamic> j) => TranscriptLine(
    speaker: asString(j['speaker'], 'system'),
    text: asString(j['text']),
    offsetMs: asInt(j['offset_ms']),
  );

  /// agent | customer | system
  final String speaker;
  final String text;
  final int offsetMs;
}

class Handoff {
  const Handoff({this.reason, this.notifiedUserId, this.notifiedUserName, this.transferred = false, this.at});

  factory Handoff.fromJson(Map<String, dynamic> j) => Handoff(
    reason: asStringOrNull(j['reason']),
    notifiedUserId: asStringOrNull(j['notified_user_id']),
    notifiedUserName: asStringOrNull(j['notified_user_name']),
    transferred: asBool(j['transferred']),
    at: parseDate(j['at']),
  );

  final String? reason;
  final String? notifiedUserId;
  final String? notifiedUserName;
  final bool transferred;
  final DateTime? at;
}

class AICallDetail {
  const AICallDetail({
    required this.call,
    this.intelligence,
    this.transcript = const [],
    this.recordingId,
    this.handoff,
  });

  factory AICallDetail.fromJson(Map<String, dynamic> j) => AICallDetail(
    call: AICall.fromJson(j),
    intelligence: j['intelligence'] is Map ? CallIntelligence.fromJson(asMap(j['intelligence'])) : null,
    transcript: asList(j['transcript'], TranscriptLine.fromJson),
    recordingId: asStringOrNull(j['recording_id']),
    handoff: j['handoff'] is Map ? Handoff.fromJson(asMap(j['handoff'])) : null,
  );

  final AICall call;
  final CallIntelligence? intelligence;
  final List<TranscriptLine> transcript;
  final String? recordingId;
  final Handoff? handoff;
}

class ProviderStatus {
  const ProviderStatus({this.provider, this.configured = false, this.model});

  factory ProviderStatus.fromJson(Map<String, dynamic> j) => ProviderStatus(
    provider: asStringOrNull(j['provider']),
    configured: asBool(j['configured']),
    model: asStringOrNull(j['model']),
  );

  final String? provider;
  final bool configured;
  final String? model;
}

class VoiceStatus {
  const VoiceStatus({
    required this.llm,
    required this.stt,
    required this.tts,
    required this.telephony,
    this.supportsAiStreaming = false,
  });

  factory VoiceStatus.fromJson(Map<String, dynamic> j) {
    final tel = asMap(j['telephony']);
    return VoiceStatus(
      llm: ProviderStatus.fromJson(asMap(j['llm'])),
      stt: ProviderStatus.fromJson(asMap(j['stt'])),
      tts: ProviderStatus.fromJson(asMap(j['tts'])),
      telephony: ProviderStatus.fromJson(tel),
      supportsAiStreaming: asBool(tel['supports_ai_streaming']),
    );
  }

  final ProviderStatus llm;
  final ProviderStatus stt;
  final ProviderStatus tts;
  final ProviderStatus telephony;
  final bool supportsAiStreaming;

  bool get readyForLiveCalls =>
      llm.configured && stt.configured && tts.configured && telephony.configured && supportsAiStreaming;
}

class TestReply {
  const TestReply({required this.reply, this.actions = const []});

  factory TestReply.fromJson(Map<String, dynamic> j) {
    final raw = j['actions'];
    final actions = raw is List
        ? raw.map((a) => a is Map ? asString(a['type'] ?? a['name'] ?? a) : a.toString()).toList()
        : <String>[];
    return TestReply(reply: asString(j['reply']), actions: actions);
  }

  final String reply;
  final List<String> actions;
}
