import 'package:flutter/material.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/app/router.dart';

class MyLoopApp extends StatelessWidget {
  const MyLoopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MyLoop',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
