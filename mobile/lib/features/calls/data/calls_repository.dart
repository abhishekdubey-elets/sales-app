import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/date_range_filter.dart';
import '../../../core/models/page_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'call_models.dart';

final callsRepositoryProvider = Provider<CallsRepository>((ref) => CallsRepository(ref.watch(apiClientProvider)));

class CallQuery {
  const CallQuery({this.salespersonId, this.leadId, this.status, this.outcome, this.direction, this.range});

  final String? salespersonId;
  final String? leadId;
  final String? status;
  final String? outcome;
  final String? direction;
  final DateRangeFilter? range;

  Map<String, dynamic> toQuery() => {
    'salesperson_id': salespersonId,
    'lead_id': leadId,
    'status': status,
    'outcome': outcome,
    'direction': direction,
    ...?range?.toQuery(),
  };

  @override
  bool operator ==(Object other) =>
      other is CallQuery &&
      other.salespersonId == salespersonId &&
      other.leadId == leadId &&
      other.status == status &&
      other.outcome == outcome &&
      other.direction == direction &&
      other.range == range;

  @override
  int get hashCode => Object.hash(salespersonId, leadId, status, outcome, direction, range);
}

class CallsRepository {
  CallsRepository(this._api);

  final ApiClient _api;

  /// Asks the backend to place a call through the telephony provider.
  /// Returns only when the backend recorded the request; failures throw
  /// `ApiException` (telephony_not_configured, telephony_error, lead_busy, ...).
  Future<HumanCall> start({String? leadId, String? phoneNumber}) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/calls',
      body: compact({'lead_id': leadId, 'phone_number': phoneNumber}),
    );
    return HumanCall.fromJson(data);
  }

  /// Logs a call the salesperson will place from their own phone; returns the number to dial.
  Future<DeviceCallStart> startDevice({String? leadId, String? phoneNumber}) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/calls/device',
      body: compact({'lead_id': leadId, 'phone_number': phoneNumber}),
    );
    return DeviceCallStart.fromJson(data);
  }

  /// Reports how a phone call went (once per call).
  Future<HumanCall> deviceResult(String id, {required bool connected, required int durationSeconds}) async =>
      HumanCall.fromJson(
        await _api.post<Map<String, dynamic>>(
          '/calls/$id/device-result',
          body: {'connected': connected, 'duration_seconds': durationSeconds},
        ),
      );

  Future<PageResult<HumanCall>> list(CallQuery query, {int page = 1, int pageSize = 20}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/calls',
      query: {...query.toQuery(), 'page': page, 'page_size': pageSize},
    );
    return PageResult.fromJson(data, HumanCall.fromJson);
  }

  Future<HumanCall?> active() async {
    final data = await _api.get<dynamic>('/calls/active');
    return data is Map ? HumanCall.fromJson(Map<String, dynamic>.from(data)) : null;
  }

  Future<List<HumanCall>> recent({int limit = 20}) async =>
      asList(await _api.get<List<dynamic>>('/calls/recent', query: {'limit': limit}), HumanCall.fromJson);

  Future<HumanCall> get(String id) async => HumanCall.fromJson(await _api.get<Map<String, dynamic>>('/calls/$id'));

  Future<HumanCall> hangup(String id) async =>
      HumanCall.fromJson(await _api.post<Map<String, dynamic>>('/calls/$id/hangup'));

  Future<HumanCall> disposition(
    String id, {
    required String outcome,
    String? notes,
    DateTime? followupAt,
    String? leadStatus,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/calls/$id/disposition',
      body: compact({
        'outcome': outcome,
        'notes': notes,
        'followup_at': dateToJson(followupAt),
        'lead_status': leadStatus,
      }),
    );
    return HumanCall.fromJson(data);
  }

  Future<CallNote> addNote(String id, String body) async =>
      CallNote.fromJson(await _api.post<Map<String, dynamic>>('/calls/$id/notes', body: {'body': body}));

  Future<SignedUrl> recordingUrl(String recordingId) async =>
      SignedUrl.fromJson(await _api.get<Map<String, dynamic>>('/recordings/$recordingId/url'));

  Future<TelephonyStatus> telephonyStatus() async =>
      TelephonyStatus.fromJson(await _api.get<Map<String, dynamic>>('/settings/telephony-status'));
}

final recentCallsProvider = FutureProvider.autoDispose<List<HumanCall>>(
  (ref) => ref.watch(callsRepositoryProvider).recent(),
);

final callDetailProvider = FutureProvider.autoDispose.family<HumanCall, String>(
  (ref, id) => ref.watch(callsRepositoryProvider).get(id),
);
