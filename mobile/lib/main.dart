/// MyLoop — Application Entry Point
///
/// This file bootstraps the Flutter application by initializing platform
/// bindings, Firebase services, and the Riverpod dependency injection
/// container before launching the root widget tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:myloop/app/app.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Application Bootstrap
// ─────────────────────────────────────────────────────────────────────────────

/// Application entry point.
void main() async {
  // Required before calling any plugin or async code in main().
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase. Wrapped in try-catch because on web the config
  // (firebase_options.dart) may not exist yet — the app still loads so
  // you can test the UI without a live Firebase project.
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase not configured for this platform — continue without it.
  }

  // ProviderScope is the root of all Riverpod state — it must wrap the
  // entire widget tree so that providers can be read/watched anywhere.
  runApp(const ProviderScope(child: MyLoopApp()));
}
