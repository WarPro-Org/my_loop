/// Widget tests for the debug mock-walk designer's mode control (#160 review).
///
/// After a START the simulator stays on for the rest of the app session, so the
/// designer must offer an explicit way back to real GPS, and loading a saved
/// route (whose persisted config always has `enabled: false`) must not change
/// the mode as a side effect.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:myloop/features/dev/mock_walk_screen.dart';
import 'package:myloop/shared/services/location_service.dart';
import 'package:myloop/shared/services/mock/mock_location_service.dart';
import 'package:myloop/shared/services/mock/mock_route_store.dart';
import 'package:myloop/shared/services/mock/mock_walk_config.dart';

const _savedRouteName = 'Office block loop';
const _savedStart = LatLng(37.5, -122.1);

/// Serves a fixed library from memory so the screen never touches the disk.
class _FakeLibrary extends MockRouteLibraryNotifier {
  @override
  Future<MockRouteLibrary> build() async => MockRouteLibrary(routes: [
        SavedMockRoute(
          name: _savedRouteName,
          savedAt: DateTime(2026, 7, 1),
          config: const MockWalkConfig(startPoint: _savedStart),
        ),
      ]);
}

Future<ProviderContainer> _pumpWithMockOn(WidgetTester tester) async {
  final container = ProviderContainer(overrides: [
    mockRouteLibraryProvider.overrideWith(_FakeLibrary.new),
  ]);
  addTearDown(container.dispose);
  // The state a START leaves behind: the mock is on.
  final notifier = container.read(mockWalkConfigProvider.notifier);
  notifier.update(container.read(mockWalkConfigProvider).copyWith(enabled: true));

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: MockWalkScreen()),
  ));
  await tester.pump();
  return container;
}

void main() {
  testWidgets('"Use real GPS" switches locationServiceProvider back to the real service',
      (tester) async {
    final container = await _pumpWithMockOn(tester);
    expect(container.read(locationServiceProvider), isA<MockLocationService>());

    await tester.tap(find.byKey(MockWalkScreen.mockOffKey));
    await tester.pump();

    expect(container.read(mockWalkConfigProvider).enabled, isFalse);
    expect(MockWalkMode.active, isFalse);
    final service = container.read(locationServiceProvider);
    expect(service, isNot(isA<MockLocationService>()));
    expect(service.runtimeType, LocationService);
    // The control disappears once there is nothing to turn off.
    expect(find.byKey(MockWalkScreen.mockOffKey), findsNothing);
  });

  testWidgets('loading a saved route keeps the mock on', (tester) async {
    final container = await _pumpWithMockOn(tester);

    final tile = find.text(_savedRouteName);
    await tester.scrollUntilVisible(tile, 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(tile);
    await tester.pump();

    final config = container.read(mockWalkConfigProvider);
    expect(config.startPoint, _savedStart);
    expect(config.enabled, isTrue);
    expect(container.read(locationServiceProvider), isA<MockLocationService>());
  });
}
