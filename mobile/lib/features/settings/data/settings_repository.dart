import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/page_result.dart';
import '../../../core/network/api_client.dart';
import '../../calls/data/call_models.dart';
import 'settings_models.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(apiClientProvider)),
);

class SettingsRepository {
  SettingsRepository(this._api);

  final ApiClient _api;

  Future<OrgSettings> get() async => OrgSettings.fromJson(await _api.get<Map<String, dynamic>>('/settings'));

  Future<OrgSettings> update(Map<String, dynamic> body) async =>
      OrgSettings.fromJson(await _api.patch<Map<String, dynamic>>('/settings', body: body));

  Future<TelephonyStatus> telephonyStatus() async =>
      TelephonyStatus.fromJson(await _api.get<Map<String, dynamic>>('/settings/telephony-status'));

  Future<PageResult<AuditLog>> auditLogs({String? action, String? entityType, int page = 1, int pageSize = 30}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/audit-logs',
      query: {'action': action, 'entity_type': entityType, 'page': page, 'page_size': pageSize},
    );
    return PageResult.fromJson(data, AuditLog.fromJson);
  }
}

final orgSettingsProvider = FutureProvider.autoDispose<OrgSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).get(),
);

final telephonyStatusProvider = FutureProvider.autoDispose<TelephonyStatus>(
  (ref) => ref.watch(settingsRepositoryProvider).telephonyStatus(),
);
