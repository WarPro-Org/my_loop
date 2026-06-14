import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:myloop/shared/services/app_logger.dart';
import 'package:myloop/shared/services/trace_context.dart';

void main() {
  group('AppLogger ring buffer', () {
    setUp(() {
      AppLogger.init();
      AppLogger.clear();
    });

    test('retains emitted records for the crash-report tail', () async {
      Logger('Test').severe('boom-marker');
      await Future<void>.delayed(Duration.zero); // let the async listener run

      expect(AppLogger.tail().any((l) => l.contains('boom-marker')), isTrue);
    });

    test('tail honours the requested max', () async {
      for (var i = 0; i < 40; i++) {
        Logger('Test').info('line-$i');
      }
      await Future<void>.delayed(Duration.zero);

      expect(AppLogger.tail(max: 10).length, lessThanOrEqualTo(10));
    });
  });

  group('TraceContext', () {
    test('builds a valid W3C traceparent and records the trace id', () {
      final traceparent = TraceContext.newTraceparent();
      final parts = traceparent.split('-');

      expect(parts.length, 4);
      expect(parts[0], '00'); // version
      expect(parts[1].length, 32); // 128-bit trace id
      expect(parts[2].length, 16); // 64-bit span id
      expect(parts[3], '01'); // sampled
      expect(TraceContext.lastTraceId, parts[1]);
    });

    test('each call rotates the trace id', () {
      final first = TraceContext.newTraceparent();
      final second = TraceContext.newTraceparent();
      expect(first, isNot(equals(second)));
    });
  });
}
