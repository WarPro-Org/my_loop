/// W3C Trace Context propagation for outbound API requests.
///
/// Each request carries a `traceparent` header; the backend adopts it as the
/// request's `Activity.TraceId` (see api Phase 1), so a single trace id ties a
/// mobile action to its server-side log lines — and to the crash report, which
/// attaches [lastTraceId]. Format: `00-<32 hex trace id>-<16 hex span id>-01`.
library;

import 'dart:math';

class TraceContext {
  TraceContext._();

  static final Random _rng = Random.secure();

  static String? _lastTraceId;

  /// Trace id of the most recent outbound request, or null if none sent yet.
  /// Referenced by the crash handler so a report points at what the user was
  /// doing when things broke.
  static String? get lastTraceId => _lastTraceId;

  /// Builds a fresh sampled `traceparent` value and records its trace id as the
  /// most recent one.
  static String newTraceparent() {
    final traceId = _hex(16); // 128-bit
    final spanId = _hex(8); //   64-bit
    _lastTraceId = traceId;
    return '00-$traceId-$spanId-01';
  }

  static String _hex(int bytes) {
    final sb = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      sb.write(_rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
