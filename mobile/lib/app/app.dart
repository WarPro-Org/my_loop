/// MyLoop — Root Application Widget
library;

import 'package:flutter/material.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/app/router.dart';
import 'package:myloop/features/splash/splash_screen.dart';

/// The root widget of the MyLoop application.
///
/// Shows the hex rush splash animation once on startup, then transitions
/// to the main app via go_router.
class MyLoopApp extends StatefulWidget {
  const MyLoopApp({super.key});

  @override
  State<MyLoopApp> createState() => _MyLoopAppState();
}

class _MyLoopAppState extends State<MyLoopApp> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
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
