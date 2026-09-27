/// FR1: `GET /api/rules` from the app, and the fingerprint (ETag) it sends back next time.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/services/api_service.dart';

const _body = {'version': 1};

/// Answers every GET with a fixed status and ETag, and records the request headers.
class _ServerDio with DioMixin implements Dio {
  _ServerDio({required this.status, this.etag}) {
    options = BaseOptions();
  }

  final int status;
  final String? etag;
  Map<String, dynamic>? sentHeaders;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    sentHeaders = options?.headers;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: status,
      data: status == HttpStatus.ok ? _body as T : null,
      headers: Headers.fromMap({
        if (etag != null) HttpHeaders.etagHeader: [etag!],
      }),
    );
  }
}

void main() {
  test('sends the saved fingerprint back in quotes; "not modified" means nothing new', () async {
    final dio = _ServerDio(status: HttpStatus.notModified);

    final result = await ApiService(dio: dio).getRules('1-abc');

    expect(dio.sentHeaders?[HttpHeaders.ifNoneMatchHeader], '"1-abc"');
    expect(result, isNull);
  });

  test('with no fingerprint yet, sends none; new rules come with theirs, quotes removed', () async {
    final dio = _ServerDio(status: HttpStatus.ok, etag: '"1-abc"');

    final result = await ApiService(dio: dio).getRules(null);

    expect(dio.sentHeaders?.containsKey(HttpHeaders.ifNoneMatchHeader), isFalse);
    expect(result?.json, _body);
    expect(result?.tag, '1-abc');
  });

  test('a weak fingerprint from a proxy is stored as the plain fingerprint', () async {
    final result = await ApiService(dio: _ServerDio(status: HttpStatus.ok, etag: 'W/"1-abc"')).getRules(null);

    expect(result?.tag, '1-abc');
  });

  test('rules without a fingerprint still apply; the next request just has none to send', () async {
    final result = await ApiService(dio: _ServerDio(status: HttpStatus.ok)).getRules(null);

    expect(result?.json, _body);
    expect(result?.tag, isNull);
  });
}
