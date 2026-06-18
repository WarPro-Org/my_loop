/// Regression test for the offline-start gate hardening on #43.
///
/// `ApiService.isServerReachable` originally caught only `DioException`. The
/// request interceptor awaits `getIdToken()`, which can raise a non-Dio
/// `FirebaseAuthException` during an offline token refresh; that throw escaped
/// the catch and surfaced as an unhandled error in `startJourney` instead of
/// the intended offline message. The probe now fails closed (treats any
/// unexpected error as unreachable). This test drives the real method into that
/// branch with a Dio whose `get` throws a non-Dio error.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/services/api_service.dart';

/// A Dio whose `get` throws a non-`DioException` error, simulating an
/// interceptor failure (e.g. an offline Firebase token refresh) that escapes
/// the `on DioException` catch.
class _ThrowingDio with DioMixin implements Dio {
  _ThrowingDio() {
    options = BaseOptions();
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) =>
      throw StateError('non-Dio probe failure');
}

void main() {
  group('ApiService.isServerReachable (#43 hardening)', () {
    test('returns false when the probe throws a non-Dio error', () async {
      final api = ApiService(dio: _ThrowingDio());

      // Pre-fix this StateError escaped isServerReachable and crashed the
      // journey-start flow; now it is classified as unreachable (fail-closed).
      expect(await api.isServerReachable(), isFalse);
    });
  });
}
