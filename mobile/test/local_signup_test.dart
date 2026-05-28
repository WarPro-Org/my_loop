import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/features/auth/local_signup_screen.dart';
import 'package:myloop/app/theme.dart';

void main() {
  // Note: LocalSignupScreen has autofocus:true which creates a cursor blink
  // timer. We need to unfocus before test ends to avoid "Timer still pending".
  group('LocalSignupScreen', () {
    Widget buildApp() => MaterialApp(
      theme: AppTheme.light,
      home: const LocalSignupScreen(),
    );

    Future<void> cleanUp(WidgetTester tester) async {
      // Unfocus the text field to stop cursor blink timer
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
    }

    testWidgets('renders name field and continue button', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('CONTINUE'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      await cleanUp(tester);
    });

    testWidgets('continue button starts disabled (opacity 0.5)', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump(const Duration(milliseconds: 250));

      final opacities = tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity));
      // The last AnimatedOpacity wraps the CONTINUE button
      final buttonOpacity = opacities.last;
      expect(buttonOpacity.opacity, 0.5);
      await cleanUp(tester);
    });

    testWidgets('typing a valid name enables button', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Robin');
      await tester.pump(const Duration(milliseconds: 250));

      final opacities = tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity));
      final buttonOpacity = opacities.last;
      expect(buttonOpacity.opacity, 1.0);
      await cleanUp(tester);
    });

    testWidgets('single character keeps button disabled', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'X');
      await tester.pump(const Duration(milliseconds: 250));

      final opacities = tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity));
      final buttonOpacity = opacities.last;
      expect(buttonOpacity.opacity, 0.5);
      await cleanUp(tester);
    });
  });
}
