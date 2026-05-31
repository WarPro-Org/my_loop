/// MyLoop — Location Service
///
/// Provides a unified interface for GPS location operations including
/// permission handling, one-shot position retrieval, and continuous
/// position streaming.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myloop/shared/constants/app_constants.dart';

/// Encapsulates all GPS interactions for the MyLoop application.
class LocationService {
  StreamSubscription<Position>? _subscription;

  /// Checks that location services are enabled and requests user permission.
  /// Returns `true` when permission is granted.
  Future<bool> requestPermission() async {
    // On web, isLocationServiceEnabled may not work reliably
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled. Please enable GPS.');
      }
    } catch (e) {
      // On web browsers, this check may throw — proceed to permission request
      if (e is Exception && e.toString().contains('disabled')) rethrow;
    }

    // Check and request permission
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied. Please allow location access in settings.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Open app settings so the user can grant permission manually
      await Geolocator.openAppSettings();
      throw Exception('Location permanently denied. Please enable location in your device settings, then try again.');
    }

    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // One-Shot Position
  // ─────────────────────────────────────────────────────────────────────────

  /// Gets the current GPS position (single reading, high accuracy).
  Future<Position> getCurrentPosition() async {
    return await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: AppConstants.gpsTimeoutSeconds),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Continuous Tracking
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a stream of position updates for continuous tracking.
  /// Only emits when the user moves at least [gpsDistanceFilterMeters] meters.
  Stream<Position> startTracking() {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: AppConstants.gpsDistanceFilterMeters,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cleanup
  // ─────────────────────────────────────────────────────────────────────────

  /// Cancels any active position stream subscription.
  void dispose() {
    _subscription?.cancel();
  }
}

/// Provides a singleton [LocationService] instance.
final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(() => service.dispose());
  return service;
});
