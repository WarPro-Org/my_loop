/// Tests for background-capable tracking settings (issue #20).
///
/// [buildTrackingSettings] is the pure piece the fix relies on: it must pick
/// platform settings that keep the position stream alive with the screen off —
/// a foreground service on Android and background updates on iOS — without
/// changing foreground/web behaviour.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myloop/shared/constants/app_constants.dart';
import 'package:myloop/shared/services/location_service.dart';

void main() {
  group('buildTrackingSettings', () {
    test('Android runs a foreground service so tracking survives screen-off', () {
      final settings = buildTrackingSettings(LocationPlatform.android);

      expect(settings, isA<AndroidSettings>());
      final android = settings as AndroidSettings;
      expect(android.foregroundNotificationConfig, isNotNull,
          reason: 'foreground service is what keeps location streaming in background');
      expect(android.distanceFilter, AppConstants.gpsDistanceFilterMeters);
      expect(android.accuracy, LocationAccuracy.high);
    });

    test('iOS enables background updates and disables auto-pause', () {
      final settings = buildTrackingSettings(LocationPlatform.ios);

      expect(settings, isA<AppleSettings>());
      final apple = settings as AppleSettings;
      expect(apple.allowBackgroundLocationUpdates, isTrue);
      expect(apple.pauseLocationUpdatesAutomatically, isFalse,
          reason: 'auto-pause would stop updates mid-walk when the device is still');
      expect(apple.showBackgroundLocationIndicator, isTrue);
      expect(apple.distanceFilter, AppConstants.gpsDistanceFilterMeters);
    });

    test('other platforms keep plain foreground settings (no regression)', () {
      final settings = buildTrackingSettings(LocationPlatform.other);

      expect(settings, isA<LocationSettings>());
      expect(settings, isNot(isA<AndroidSettings>()));
      expect(settings, isNot(isA<AppleSettings>()));
      expect(settings.distanceFilter, AppConstants.gpsDistanceFilterMeters);
    });
  });
}
