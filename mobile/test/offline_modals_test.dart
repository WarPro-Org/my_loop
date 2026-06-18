/// Regression tests for issue #36 — offline modals/screens must show an
/// explicit offline message instead of a misleading empty/zero state.
///
/// The clearest network-backed surface is [WalkHistoryScreen]: before the fix
/// an offline fetch was swallowed and the screen rendered the "No walks yet"
/// empty state, falsely implying the user had never walked. These tests pin
/// that an unreachable backend yields the offline notice, while a genuinely
/// empty history still yields the empty state and real data still renders.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/features/history/walk_history_screen.dart';
import 'package:myloop/shared/constants/app_constants.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/widgets/offline_notice.dart';

/// Fake API whose [getWalkHistory] either throws a connectivity error (to
/// simulate offline) or returns a canned page. Subclassing [ApiService] keeps
/// the real provider type; its constructor builds a Dio but performs no I/O.
class _FakeApi extends ApiService {
  final bool offline;
  final List<Map<String, dynamic>> page;
  _FakeApi({this.offline = false, this.page = const []})
      : super(baseUrl: 'http://localhost');

  @override
  Future<List<Map<String, dynamic>>> getWalkHistory({
    required String userId,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (offline) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/users/$userId/claims'),
        type: DioExceptionType.connectionError,
      );
    }
    return this.page;
  }
}

/// Provides a signed-in profile so [WalkHistoryScreen] attempts the fetch.
class _SignedInUserNotifier extends UserProfileNotifier {
  @override
  UserProfile build() => const UserProfile(userId: 'u1');
}

Future<void> _pumpScreen(WidgetTester tester, ApiService api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(api),
        userProfileProvider.overrideWith(_SignedInUserNotifier.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const WalkHistoryScreen(),
      ),
    ),
  );
  // First frame builds the loading state; second frame rebuilds after the
  // (already-completed) fetch future resolves.
  await tester.pump();
  await tester.pump();
}

void main() {
  group('WalkHistoryScreen offline state (issue #36)', () {
    testWidgets('shows offline notice — not "No walks yet" — when unreachable',
        (tester) async {
      await _pumpScreen(tester, _FakeApi(offline: true));

      expect(find.byType(OfflineNotice), findsOneWidget);
      expect(find.text(AppConstants.offlineNoticeTitle), findsOneWidget);
      // The regression: pre-fix this empty state was shown while offline.
      expect(find.text('No walks yet'), findsNothing);
    });

    testWidgets('shows empty state when history is genuinely empty',
        (tester) async {
      await _pumpScreen(tester, _FakeApi(page: const []));

      expect(find.text('No walks yet'), findsOneWidget);
      expect(find.byType(OfflineNotice), findsNothing);
    });

    testWidgets('renders walks when data is available', (tester) async {
      final api = _FakeApi(page: [
        {
          'cellCount': 3,
          'areaM2': 1200.0,
          'createdAt': DateTime.now().toIso8601String(),
        }
      ]);
      await _pumpScreen(tester, api);

      expect(find.text('3 hexes captured'), findsOneWidget);
      expect(find.byType(OfflineNotice), findsNothing);
      expect(find.text('No walks yet'), findsNothing);
    });
  });

  group('OfflineNotice widget', () {
    testWidgets('renders title and message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OfflineNotice(title: 'You\'re offline', message: 'Reconnect.'),
          ),
        ),
      );

      expect(find.text("You're offline"), findsOneWidget);
      expect(find.text('Reconnect.'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });
  });
}
