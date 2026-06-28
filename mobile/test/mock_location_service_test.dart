/// Tests for the injectable mock location source (#29).
///
/// Guards the "plug and play" contract: the mock is a real [LocationService] (so the
/// provider can swap it in) and yields a sensible first fix and stream.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:myloop/shared/services/location_service.dart';
import 'package:myloop/shared/services/mock/mock_location_service.dart';
import 'package:myloop/shared/services/mock/mock_walk_config.dart';

void main() {
  const config = MockWalkConfig(
    enabled: true,
    routeType: MockRouteType.loop,
    startPoint: LatLng(37.4220, -122.0841),
  );

  test('is a drop-in LocationService', () {
    expect(MockLocationService(config), isA<LocationService>());
  });

  test('grants permission without touching the OS', () async {
    expect(await MockLocationService(config).requestPermission(), isTrue);
  });

  test('first fix is near the route start point', () async {
    // A straight route begins AT the start point (a loop begins at its first
    // perimeter vertex, one radius away — so use straight to assert the origin).
    const straight = MockWalkConfig(
      enabled: true,
      routeType: MockRouteType.straight,
      startPoint: LatLng(37.4220, -122.0841),
    );
    final pos = await MockLocationService(straight).getCurrentPosition();
    final drift = Distance().as(
      LengthUnit.Meter,
      LatLng(pos.latitude, pos.longitude),
      straight.startPoint,
    );
    // Within a few jitter sigmas of the start.
    expect(drift, lessThan(4 * MockWalkConstants.jitterSigmaMeters));
  });

  test('startTracking emits a first position immediately', () async {
    final first = await MockLocationService(config).startTracking().first;
    expect(first.isMocked, isTrue);
  });
}
