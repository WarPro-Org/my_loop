/// MyLoop — Application Entry Point
///
/// This file bootstraps the Flutter application by initializing platform
/// bindings, Firebase services, and the Riverpod dependency injection
/// container before launching the root widget tree.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:logging/logging.dart';
import 'package:myloop/app/app.dart';
import 'package:myloop/firebase_options.dart';
import 'package:myloop/shared/services/app_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Application Bootstrap
// ─────────────────────────────────────────────────────────────────────────────

/// Application entry point.
///
/// The whole bootstrap runs inside a guarded zone so that NO uncaught error —
/// sync, async, framework, or platform — escapes unrecorded. Each path funnels
/// into [AppLogger] at `severe`, which lands in the ring buffer that crash
/// reports ship (Phase 4). The binding is created inside the zone so Flutter
/// doesn't warn about a zone mismatch with `runApp`.
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    AppLogger.init();

    // Framework errors (build/layout/paint). Still show the red screen in
    // debug, but always record it.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      Logger('FlutterError').severe(
        details.exceptionAsString(), details.exception, details.stack);
    };

    // Uncaught errors from the engine/platform (e.g. async gaps the zone
    // doesn't see). Returning true marks them handled.
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      Logger('PlatformDispatcher').severe('Uncaught platform error', error, stack);
      return true;
    };

    // Initialize Firebase. Wrapped in try-catch because on web the config
    // (firebase_options.dart) may not exist yet — the app still loads so
    // you can test the UI without a live Firebase project.
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e, s) {
      // Firebase not configured for this platform — continue without it, but
      // record it so a real init failure in the field isn't silent.
      Logger('Bootstrap').warning('Firebase init skipped/failed', e, s);
    }

    // ProviderScope is the root of all Riverpod state — it must wrap the
    // entire widget tree so that providers can be read/watched anywhere.
    runApp(const ProviderScope(child: MyLoopApp()));
  }, (error, stack) {
    // Final safety net: anything uncaught in the zone.
    Logger('Zone').severe('Uncaught zone error', error, stack);
  });
}
