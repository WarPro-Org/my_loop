import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/batch_drain_service.dart';
import 'package:myloop/shared/services/step_claim_queue.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// ApiService double: [claimBatchStep] is overridden so no real Dio request is made.
/// The base constructor only wires a Dio + interceptor (no network on construction).
class _FakeApi extends ApiService {
  _FakeApi(this.behaviour);

  /// Given the batch submitted, returns the response (null = transient failure).
  final Future<BatchResult?> Function(List<QueuedStepPoint> batch) behaviour;
  int calls = 0;

  @override
  Future<BatchResult?> claimBatchStep({
    required String userId,
    required String localDate,
    required String walkSessionId,
    required List<QueuedStepPoint> points,
    CancelToken? cancelToken,
  }) async {
    calls++;
    return behaviour(points);
  }
}

/// Transport whose server never answers, so a request stays in flight until
/// it is cancelled — an offline or very slow network.
class _HangingAdapter implements HttpClientAdapter {
  final reached = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (!reached.isCompleted) reached.complete();
    return Completer<ResponseBody>().future;
  }

  @override
  void close({bool force = false}) {}
}

/// The real [ApiService] over [adapter], so a cancel travels the production
/// Dio path into claimBatchStep's `DioException` branch.
ApiService _apiOver(_HangingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;
  final api = ApiService(dio: dio);
  // Drop ApiService's Firebase auth interceptor: no Firebase app in unit tests.
  dio.interceptors.removeWhere((i) => i is InterceptorsWrapper);
  return api;
}

/// Generous bound for work that must not wait on the network.
const _prompt = Duration(seconds: 5);

/// Builds a response that ACKs every submitted point (removes them from the queue).
BatchResult _ackAll(List<QueuedStepPoint> batch) => BatchResult.fromJson({
      'results': [
        for (final p in batch) {'clientId': p.clientId, 'claimed': true},
      ],
    });

QueuedStepPoint _pt(String id, {String session = 'walk-1'}) => QueuedStepPoint(
      clientId: id,
      lat: 12.34,
      lng: 56.78,
      capturedAt: DateTime.utc(2026, 6, 15, 10),
      walkSessionId: session,
    );

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('batch_drain_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<StepClaimQueue> queueWith(int count, {String session = 'walk-1'}) async {
    final q = StepClaimQueue();
    await q.init('u1');
    for (var i = 0; i < count; i++) {
      await q.enqueue(_pt('p$i', session: session));
    }
    return q;
  }

  // #120: drainNow must drain the WHOLE queue, not just one <=50-point batch.
  test('drainNow fully drains 120 queued points and returns true', () async {
    final q = await queueWith(120);
    final api = _FakeApi((batch) async => _ackAll(batch));
    final svc = BatchDrainService(queue: q, api: api, userId: 'u1');

    final ok = await svc.drainNow();

    expect(ok, isTrue);
    expect(q.isEmpty, isTrue);
    // 120 points / 50 per batch = 3 network calls.
    expect(api.calls, 3);
    svc.dispose();
  });

  // #120: a failure mid-drain aborts and preserves the remaining points.
  test('drainNow returns false and keeps remaining points when a batch fails', () async {
    final q = await queueWith(120);
    var call = 0;
    // First batch ACKs, second batch fails (null), rest never attempted.
    final api = _FakeApi((batch) async {
      call++;
      return call == 1 ? _ackAll(batch) : null;
    });
    final svc = BatchDrainService(queue: q, api: api, userId: 'u1');

    final ok = await svc.drainNow();

    expect(ok, isFalse);
    expect(q.length, 70, reason: 'the 50 acked points are gone; 70 remain intact');
    svc.dispose();
  });

  // #119: while the backoff window is open, _tryDrain must not hit the network.
  test('no network attempt occurs inside the backoff window after failures', () async {
    final q = await queueWith(10);
    var now = DateTime(2026, 6, 15, 10, 0, 0);
    var failing = true;
    final api = _FakeApi((batch) async => failing ? null : _ackAll(batch));
    final svc = BatchDrainService(
      queue: q,
      api: api,
      userId: 'u1',
      clock: () => now,
    );

    // First attempt fails → opens a backoff window (2^1 = 2s).
    expect(await svc.drainNow(), isFalse);
    expect(api.calls, 1);
    expect(svc.isInBackoff, isTrue);

    // Further attempts inside the window make NO network call.
    expect(await svc.drainNow(), isFalse);
    expect(await svc.drainNow(), isFalse);
    expect(api.calls, 1, reason: 'backoff must suppress network attempts');

    // Advance past the window and let the API succeed — a new attempt is made.
    now = now.add(const Duration(seconds: 3));
    failing = false;
    expect(svc.isInBackoff, isFalse);
    expect(await svc.drainNow(), isTrue);
    expect(api.calls, 2);
    expect(q.isEmpty, isTrue);
    svc.dispose();
  });

  // #119: consecutive failures grow the backoff window (exponential), capped at 30s.
  test('backoff window grows with consecutive failures', () async {
    final q = await queueWith(10);
    var now = DateTime(2026, 6, 15, 10, 0, 0);
    final api = _FakeApi((batch) async => null); // always fails
    final svc = BatchDrainService(queue: q, api: api, userId: 'u1', clock: () => now);

    await svc.drainNow(); // failure #1 → 2s window
    now = now.add(const Duration(seconds: 2));
    await svc.drainNow(); // failure #2 → 4s window
    // 3s in, still inside the 4s window.
    now = now.add(const Duration(seconds: 3));
    expect(svc.isInBackoff, isTrue);
    // Only two real attempts happened (one per expired window).
    expect(api.calls, 2);
    svc.dispose();
  });

  // A transient DioException is treated as a retryable failure (opens backoff), not a crash.
  test('a DioException opens the backoff window', () async {
    final q = await queueWith(10);
    final api = _FakeApi((batch) async =>
        throw DioException(requestOptions: RequestOptions(path: '/x')));
    final svc = BatchDrainService(queue: q, api: api, userId: 'u1');

    final ok = await svc.drainNow();

    expect(ok, isFalse);
    expect(svc.isInBackoff, isTrue);
    expect(q.length, 10, reason: 'nothing acked, points preserved');
    svc.dispose();
  });

  // #110 round 2: sign-out cancels the in-flight request instead of waiting it out.
  test('claimBatchStep returns null for a cancelled request, never a rejection', () async {
    final adapter = _HangingAdapter();
    final api = _apiOver(adapter);
    final cancel = CancelToken();
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    addTearDown(() => Logger.root.level = previousLevel);
    final apiLogs = <LogRecord>[];
    final logSub = Logger.root.onRecord.where((r) => r.loggerName == 'API').listen(apiLogs.add);
    addTearDown(logSub.cancel);

    final pending = api.claimBatchStep(
      userId: 'u1',
      localDate: '2026-06-15',
      walkSessionId: 'walk-1',
      points: [_pt('p0')],
      cancelToken: cancel,
    );
    await adapter.reached.future;
    cancel.cancel();

    expect(await pending.timeout(_prompt), isNull);
    // It took the DioException cancel branch: no transient-failure or
    // unexpected-error warning, just the fine-level cancel record.
    expect(apiLogs.where((r) => r.level >= Level.WARNING), isEmpty);
    expect(apiLogs.where((r) => r.level == Level.FINE), hasLength(1));
  });

  test('dispose(cancelInFlight) ends an unanswered batch promptly and leaves the queue untouched',
      () async {
    final q = await queueWith(5);
    final ids = q.peek(5).map((p) => p.clientId).toList();
    final adapter = _HangingAdapter();
    final svc = BatchDrainService(queue: q, api: _apiOver(adapter), userId: 'u1');
    final rejections = <String>[];
    svc.onRejection.listen(rejections.add);

    svc.notifyEnqueue(); // at threshold → drain starts and hangs on the network
    await adapter.reached.future;
    await svc.dispose(cancelInFlight: true).timeout(_prompt);

    expect(q.peek(5).map((p) => p.clientId), ids, reason: 'memory untouched');
    final reopened = StepClaimQueue();
    await reopened.init('u1');
    expect(reopened.peek(5).map((p) => p.clientId), ids, reason: 'disk == memory');
    expect(rejections, isEmpty, reason: 'a cancel is not a server rejection');
  });
}
