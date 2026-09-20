/// Tests for the API host resolution (#139 D8).
///
/// Before this, `apiBaseUrl` fell back to a hardcoded ngrok tunnel in every
/// build mode. Nothing in `.github/`, `scripts/` or `mobile/` sets `API_URL`,
/// so a release build shipped pointing at that tunnel — and the URL lives
/// inside the binary, so every installed copy keeps calling it. A reclaimable
/// ngrok subdomain receiving Firebase JWTs and GPS coordinates is the failure
/// these tests exist to prevent.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/services/api_service.dart';

void main() {
  const configured = 'https://api.myloop.example';

  group('resolveApiBaseUrl', () {
    test('uses API_URL when supplied, in release/profile', () {
      expect(
        resolveApiBaseUrl(fromEnvironment: configured, isDebug: false),
        configured,
      );
    });

    test('uses API_URL when supplied, in debug', () {
      expect(
        resolveApiBaseUrl(fromEnvironment: configured, isDebug: true),
        configured,
      );
    });

    test('release or profile with no API_URL resolves empty — never a baked-in default', () {
      final resolved = resolveApiBaseUrl(fromEnvironment: '', isDebug: false);
      expect(resolved, isEmpty);
      expect(resolved, isNot(contains('ngrok')),
          reason: 'a shipped binary must not carry a dev tunnel as its fallback');
    });

    test('debug with no API_URL falls back so flutter run needs no flags', () {
      final resolved = resolveApiBaseUrl(fromEnvironment: '', isDebug: true);
      expect(resolved, isNotEmpty);
      expect(resolved, startsWith('https://'));
    });
  });

  group('apiBaseUrlConfigError', () {
    test('an empty host is fatal and names the missing define', () {
      final error = apiBaseUrlConfigError('');
      expect(error, isNotNull);
      expect(error, contains('API_URL'));
      expect(error, contains('--dart-define'));
    });

    test('a configured host is not an error', () {
      expect(apiBaseUrlConfigError(configured), isNull);
    });

    // The bootstrap throws on a non-null result, so this pairing is what makes
    // a misconfigured release fail loudly instead of calling an unintended host.
    test('release or profile with no API_URL produces a fatal config error end to end', () {
      final resolved = resolveApiBaseUrl(fromEnvironment: '', isDebug: false);
      expect(apiBaseUrlConfigError(resolved), isNotNull);
    });

    test('debug with no API_URL boots fine', () {
      final resolved = resolveApiBaseUrl(fromEnvironment: '', isDebug: true);
      expect(apiBaseUrlConfigError(resolved), isNull);
    });
  });
}
