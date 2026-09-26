/// MyLoop — Root Application Widget
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/rules/game_rules_provider.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/app/router.dart';
import 'package:myloop/features/auth/user_session_teardown.dart';
import 'package:myloop/features/moderation/blocked_users.dart';
import 'package:myloop/features/splash/splash_screen.dart';
import 'package:myloop/shared/services/realtime_resync.dart';

/// The root widget of the MyLoop application.
///
/// Shows the hex rush splash animation once on startup, then transitions
/// to the main app via go_router.
class MyLoopApp extends ConsumerStatefulWidget {
  const MyLoopApp({super.key});

  @override
  ConsumerState<MyLoopApp> createState() => _MyLoopAppState();
}

class _MyLoopAppState extends ConsumerState<MyLoopApp> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    // App-lifetime: tears down user-bound state when Firebase ends the session
    // behind the UI's back (revoked token, account deleted elsewhere — #110).
    ref.watch(forcedSignOutGuardProvider);
    // App-lifetime: starts loading the block list as soon as an account signs in, before any
    // realtime event or map tap needs it, and keeps it alive for the session (#195 review).
    // Listened to, not watched: a block-list change must not rebuild the app root.
    ref.listen(blockedUsersProvider, (_, _) {});
    // Loads the game rules (saved copy, then a server check) as soon as the app opens (FR1).
    ref.listen(gameRulesProvider, (_, _) {});
    if (!_splashDone) {
      return MaterialApp(
        title: 'MyLoop',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: SplashScreen(onComplete: () => setState(() => _splashDone = true)),
      );
    }

    return Consumer(
      builder: (context, ref, child) {
        // Reading this once keeps it alive for the app session — it wires
        // reconnect/foreground-resume resync (#111). The provider itself
        // never rebuilds this subtree; it's read purely for its side effect.
        ref.watch(realtimeResyncProvider);
        return child!;
      },
      child: MaterialApp.router(
        title: 'MyLoop',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
      ),
    );
  }
}
