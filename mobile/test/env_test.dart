import 'package:elets_salescall_ai/core/config/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Env.normalizeServerUrl', () {
    test('adds http:// to a bare host:port', () {
      expect(Env.normalizeServerUrl(' 192.168.1.20:8000 '), 'http://192.168.1.20:8000');
    });

    test('keeps https and strips trailing slash and /api/v1', () {
      expect(Env.normalizeServerUrl('https://api.example.com/api/v1/'), 'https://api.example.com');
      expect(Env.normalizeServerUrl('https://example.com/sales/'), 'https://example.com/sales');
    });

    test('rejects empty and non-http input', () {
      expect(Env.normalizeServerUrl(''), isNull);
      expect(Env.normalizeServerUrl('ftp://host'), isNull);
      expect(Env.normalizeServerUrl('http://'), isNull);
    });
  });
}
