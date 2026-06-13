/// Central logging setup for the app.
///
/// Wraps the `logging` package so call sites use ordinary named loggers
/// (`Logger('SignalR').fine(...)`) while a single root listener fans every
/// record out to two sinks:
///   1. the debug console (debug builds only — `debugPrint` is a no-op in
///      release anyway), and
///   2. an in-memory **ring buffer** that survives RELEASE builds and is
///      attached to crash reports (Phase 4) so we can see what happened in the
///      seconds before a crash on a beta tester's device.
///
/// Build-mode discipline (see spec §5.4): in release we keep only WARNING+ to
/// stay light, but those — the records that actually matter for diagnostics —
/// are always retained in the ring buffer. Keep log MESSAGES free of PII
/// (no tokens, email, or raw GPS streams).
library;

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

class AppLogger {
  AppLogger._();

  /// How many recent records to retain for crash-report tails.
  static const int _ringCapacity = 200;

  static final ListQueue<String> _ring = ListQueue<String>(_ringCapacity);

  static bool _initialized = false;

  /// Installs the root log listener. Idempotent; call once during bootstrap.
  static void init() {
    if (_initialized) return;
    _initialized = true;

    // Everything in debug; only WARNING+ in release.
    Logger.root.level = kReleaseMode ? Level.WARNING : Level.ALL;

    Logger.root.onRecord.listen((record) {
      // Build the full line ONCE — including error + stack — so the ring buffer
      // (which ships with crash reports in release) carries the same diagnostic
      // detail as the console, not just the static message.
      final line = _format(record);

      // Ring buffer — always retained; this is the crash-report tail.
      if (_ring.length >= _ringCapacity) _ring.removeFirst();
      _ring.add(line);

      // Console — debug builds only.
      if (kDebugMode) debugPrint(line);
    });
  }

  static String _format(LogRecord r) {
    final buffer = StringBuffer()
      ..write('[${r.time.toIso8601String()}] ${r.level.name.padRight(7)} ')
      ..write('[${r.loggerName}] ${r.message}');
    if (r.error != null) buffer.write('\n  error: ${r.error}');
    if (r.stackTrace != null) buffer.write('\n${r.stackTrace}');
    return buffer.toString();
  }

  /// The most recent log lines (oldest first), capped at [max].
  /// Attached to crash reports as the `logTail`.
  static List<String> tail({int max = 100}) {
    final all = _ring.toList(growable: false);
    if (all.length <= max) return all;
    return all.sublist(all.length - max);
  }

  /// Test/diagnostic hook — clears the ring buffer.
  @visibleForTesting
  static void clear() => _ring.clear();
}
