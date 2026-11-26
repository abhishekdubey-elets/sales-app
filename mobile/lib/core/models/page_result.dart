import '../utils/json.dart';

/// `{"items": [...], "total": 120, "page": 1, "page_size": 20}`
class PageResult<T> {
  const PageResult({required this.items, required this.total, required this.page, required this.pageSize});

  factory PageResult.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) => PageResult<T>(
    items: asList(json['items'], parse),
    total: asInt(json['total']),
    page: asInt(json['page'], 1),
    pageSize: asInt(json['page_size'], 20),
  );

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;

  bool get hasMore => page * pageSize < total;
}

/// `{url, expires_at}` returned for recordings and exports.
class SignedUrl {
  const SignedUrl({required this.url, this.expiresAt});

  factory SignedUrl.fromJson(Map<String, dynamic> json) =>
      SignedUrl(url: asString(json['url']), expiresAt: parseDate(json['expires_at']));

  final String url;
  final DateTime? expiresAt;
}
