/// MyLoop — Root Application Widget
///
/// Defines [MyLoopApp], the top-level widget that configures Material Design
/// theming and declarative routing via `go_router`. This widget is mounted
/// once by [main] inside a [ProviderScope] and remains in the tree for the
/// entire application lifecycle.
library;

import 'package:flutter/material.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/app/router.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Root Widget
// ─────────────────────────────────────────────────────────────────────────────

/// The root widget of the MyLoop application.
///
/// Responsibilities:
/// - Applies the global light theme defined in [AppTheme].
/// - Delegates navigation to the [GoRouter] instance declared in `router.dart`.
/// - Disables the debug banner for production-ready screenshots and recordings.
///
/// This widget is intentionally a [StatelessWidget] because all mutable state
/// lives in Riverpod providers or within individual feature screens.
class MyLoopApp extends StatelessWidget {
  /// Creates the root application widget.
  const MyLoopApp({super.key});

  @override
  Widget build(BuildContext context) {
    // MaterialApp.router integrates with GoRouter's RouteInformationProvider
    // and RouterDelegate for declarative, URL-driven navigation.
    return MaterialApp.router(
      title: 'MyLoop',
      debugShowCheckedModeBanner: false, // Hide the "DEBUG" ribbon in the top-right corner.
      theme: AppTheme.light, // Light mode theme; dark mode can be added via `darkTheme:`.
      routerConfig: router, // GoRouter configuration from router.dart.
    );
  }
}
