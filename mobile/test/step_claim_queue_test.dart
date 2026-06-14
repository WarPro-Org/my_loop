import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/services/step_claim_queue.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Returns a fixed temp directory for [getApplicationDocumentsPath] so the
/// queue's write-ahead log lands on a real, inspectable file during tests.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);

  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

QueuedStepPoint _pt(String id) => QueuedStepPoint(
      clientId: id,
      lat: 12.34,
      lng: 56.78,
      capturedAt: DateTime.utc(2026, 6, 15, 10),
    );

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('step_claim_queue_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('enqueue/peek/removeProcessed roundtrip survives a reopen', () async {
    final q = StepClaimQueue();
    await q.init();

    await q.enqueue(_pt('a'));
    await q.enqueue(_pt('b'));
    await q.enqueue(_pt('c'));

    expect(q.length, 3);
    expect(q.peek(2).map((p) => p.clientId), ['a', 'b']);

    await q.removeProcessed({'b'});
    expect(q.getAll().map((p) => p.clientId), ['a', 'c']);

    // The WAL on disk must agree with memory after a removal.
    final reopened = StepClaimQueue();
    await reopened.init();
    expect(reopened.getAll().map((p) => p.clientId), ['a', 'c']);
  });

  test('clear empties both memory and the on-disk WAL', () async {
    final q = StepClaimQueue();
    await q.init();
    await q.enqueue(_pt('a'));
    await q.clear();

    expect(q.isEmpty, isTrue);

    final reopened = StepClaimQueue();
    await reopened.init();
    expect(reopened.isEmpty, isTrue);
  });

  // Regression for the StepClaimQueue write-lock (PR #17): an [enqueue] append
  // must not interleave with a [removeProcessed]/[clear] rewrite. Pre-fix, the
  // rewrite snapshots the cache, the append lands on the file, then the
  // rewrite's atomic rename replaces the file with a snapshot that lacks the
  // just-appended point — so the disk WAL silently diverges from memory and a
  // queued GPS point is lost if the OS kills the app. The invariant guarded
  // here: after any awaited batch of operations, a freshly-reopened queue
  // (reading only disk) must match the live queue's in-memory view.
  test('racing enqueue against a rewrite never desyncs disk from memory',
      () async {
    for (var i = 0; i < 25; i++) {
      final q = StepClaimQueue();
      await q.init();
      await q.clear();
      await q.enqueue(_pt('seed'));

      // Fire a rewrite (removeProcessed) and two appends (enqueue) without
      // awaiting between them, so they race on the same file.
      await Future.wait<void>([
        q.removeProcessed({'seed'}),
        q.enqueue(_pt('x$i')),
        q.enqueue(_pt('y$i')),
      ]);

      final reopened = StepClaimQueue();
      await reopened.init();

      expect(
        reopened.getAll().map((p) => p.clientId).toSet(),
        q.getAll().map((p) => p.clientId).toSet(),
        reason: 'disk and memory diverged on iteration $i',
      );
    }
  });
}
