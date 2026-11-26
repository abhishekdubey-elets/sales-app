import 'package:dio/dio.dart';

/// Error returned by the backend as `{"detail": "...", "code": "...", ...extra}`,
/// or a transport failure (no status code).
class ApiException implements Exception {
  const ApiException({required this.message, this.statusCode, this.code, this.extra = const {}});

  factory ApiException.fromDio(DioException e) {
    final response = e.response;
    if (response == null) {
      final msg = switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => 'The server took too long to respond. Check your connection and try again.',
        DioExceptionType.cancel => 'Request cancelled.',
        _ => 'Can\'t reach the server. Check your internet connection.',
      };
      return ApiException(message: msg, code: 'network_error');
    }
    final data = response.data;
    String message = 'Something went wrong (HTTP ${response.statusCode}).';
    String? code;
    final extra = <String, dynamic>{};
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is List && detail.isNotEmpty) {
        // FastAPI validation errors: [{loc: [...], msg: "..."}]
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          final loc = first['loc'];
          final field = loc is List && loc.isNotEmpty ? loc.last.toString() : null;
          message = field != null ? '$field: ${first['msg']}' : first['msg'].toString();
        }
        code ??= 'validation_error';
      }
      code = data['code']?.toString() ?? code;
      data.forEach((k, v) {
        if (k != 'detail' && k != 'code') extra[k.toString()] = v;
      });
    } else if (data is String && data.isNotEmpty && data.length < 300) {
      message = data;
    }
    return ApiException(message: message, statusCode: response.statusCode, code: code, extra: extra);
  }

  final String message;
  final int? statusCode;
  final String? code;
  final Map<String, dynamic> extra;

  bool get isNetwork => statusCode == null;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;

  /// Message to show to the user; adds guidance for calling-related codes.
  String get friendlyMessage => switch (code) {
    'telephony_not_configured' =>
      'Calling is not set up yet: no telephony provider is configured on the server. '
          'Ask your admin to configure one. No call was placed.',
    'telephony_error' => 'The telephony provider rejected the call request, so no call was placed. $message',
    'opted_out' => 'This number has opted out of calls. It can\'t be dialled.',
    'outside_calling_hours' => 'Calls are only allowed during permitted calling hours. $message',
    'lead_busy' => 'This lead is already on another call (human or AI). Try again when it ends.',
    'consent_required' => 'This lead hasn\'t given consent for AI calls.',
    'llm_not_configured' => 'No AI language model is configured on the server, so the agent can\'t reply yet.',
    'duplicate_lead' => 'A lead with this phone number or email already exists.',
    'forbidden' => 'You don\'t have permission to do that.',
    _ => message,
  };

  @override
  String toString() => friendlyMessage;
}

/// User-facing text for any error thrown by a repository.
String errorMessage(Object error) {
  if (error is ApiException) return error.friendlyMessage;
  if (error is DioException) return ApiException.fromDio(error).friendlyMessage;
  return 'Unexpected error: $error';
}
