/// MyLoop — Root Application Widget
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/app/router.dart';
import 'package:myloop/features/auth/user_session_teardown.dart';
import 'package:myloop/features/splash/splash_screen.dart';

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
    if (!_splashDone) {
      return MaterialApp(
        title: 'MyLoop',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: SplashScreen(onComplete: () => setState(() => _splashDone = true)),
      );
    }

    return MaterialApp.router(
      title: 'MyLoop',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
