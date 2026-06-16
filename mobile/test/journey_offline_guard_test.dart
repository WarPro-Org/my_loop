/// Regression tests for issue #35 — a journey must not start while offline.
///
/// Hex capture is server-validated (anti-cheat + claim authority), so a walk
/// started with no server reachable gives the user no preview, no claims, and
/// no feedback. [JourneyController.startJourney] now probes server reachability
/// first and blocks with a clear message instead of starting GPS tracking.
///
/// These tests are hermetic: the API and location services are faked, so no
/// network or platform GPS channel is touched.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/features/journey/journey_controller.dart';
import 'package:myloop/shared/constants/app_constants.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/location_service.dart';

/// API double whose reachability answer is fixed by the test.
class _FakeApiService extends ApiService {
  _FakeApiService(this._reachable);
  final bool _reachable;

  @override
  Future<bool> isServerReachable() async => _reachable;
}

/// Location double that records whether the journey got past the offline gate.
/// Denies permission so `startJourney` returns without touching real GPS.
class _FakeLocationService extends LocationService {
  bool permissionRequested = false;

  @override
  Future<bool> requestPermission() async {
    permissionRequested = true;
    return false;
  }
}

ProviderContainer _containerWith(_FakeApiService api, _FakeLocationService loc) {
  final container = ProviderContainer(overrides: [
    apiServiceProvider.overrideWithValue(api),
    locationServiceProvider.overrideWithValue(loc),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('startJourney offline gate (issue #35)', () {
    test('blocks with the offline message when the server is unreachable', () async {
      final loc = _FakeLocationService();
      final container = _containerWith(_FakeApiService(false), loc);
      final controller = container.read(journeyControllerProvider.notifier);

      await controller.startJourney();

      final state = container.read(journeyControllerProvider);
      expect(state.status, JourneyStatus.idle);
      expect(state.error, AppConstants.offlineStartJourneyMessage);
      // Gate must short-circuit before any GPS/permission work.
      expect(loc.permissionRequested, isFalse);
    });

    test('passes the gate and proceeds when the server is reachable', () async {
      final loc = _FakeLocationService();
      final container = _containerWith(_FakeApiService(true), loc);
      final controller = container.read(journeyControllerProvider.notifier);

      await controller.startJourney();

      final state = container.read(journeyControllerProvider);
      // Online: the offline gate is not the thing that stopped us — the faked
      // permission denial is, proving the journey moved past the connectivity check.
      expect(loc.permissionRequested, isTrue);
      expect(state.error, isNot(AppConstants.offlineStartJourneyMessage));
      expect(state.status, JourneyStatus.idle);
    });
  });
}
