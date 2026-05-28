/// MyLoop — Location Service
///
/// Provides a unified interface for GPS location operations including
/// permission handling, one-shot position retrieval, and continuous
/// position streaming. This service abstracts the `geolocator` package
/// so that consuming code doesn't depend directly on platform specifics.
///
/// Usage:
///   - Call [requestPermission] before any location operation to ensure
///     the user has granted access and the device GPS is enabled.
///   - Use [getCurrentPosition] for a single fix (e.g., centering the map).
///   - Use [startTracking] during an active journey to receive a stream of
///     position updates as the user moves.
///
/// Lifecycle:
///   Managed via Riverpod's [locationServiceProvider] — the service is
///   automatically disposed (cancelling any active stream subscription)
///   when the provider is no longer watched.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Location Service
// ─────────────────────────────────────────────────────────────────────────────

/// Encapsulates all GPS interactions for the MyLoop application.
///
/// This class does NOT hold state about the user's position — it only
/// provides the means to obtain positions. State management (e.g., storing
/// the latest position) is handled by Riverpod providers at the feature level.
class LocationService {
  /// Internal subscription reference used to cancel ongoing position streams
  /// when [dispose] is called. May be `null` if no stream is active.
  StreamSubscription<Position>? _subscription;

  // ─────────────────────────────────────────────────────────────────────────
  // Permission Handling
  // ─────────────────────────────────────────────────────────────────────────

  /// Checks that location services are enabled and requests user permission.
  ///
  /// Returns `true` when permission is granted (either `whileInUse` or
  /// `always`). Throws a descriptive [Exception] if:
  ///   - GPS hardware/service is turned off on the device.
  ///   - The user denies the permission prompt.
  ///   - The user has permanently denied location access (requires manual
  ///     Settings navigation).
  ///
  /// Should be called at the start of any location-dependent workflow
  /// (e.g., before starting a journey or showing the map).
  Future<bool> requestPermission() async {
    // On web, isLocationServiceEnabled may not work reliably.
    // We try it but don't block on failure.
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

  /// Retrieves the device's current GPS position as a single future.
  ///
  /// Configuration:
  ///   - **Accuracy**: `high` — uses GPS hardware for best precision (~3 m).
  ///   - **Timeout**: 15 seconds — prevents indefinite blocking when GPS
  ///     signal is weak (indoors, urban canyons).
  ///
  /// Returns a [Position] containing latitude, longitude, altitude, speed,
  /// accuracy, and timestamp.
  Future<Position> getCurrentPosition() async {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Continuous Tracking
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a broadcast stream of [Position] updates for continuous tracking.
  ///
  /// Configuration:
  ///   - **Accuracy**: `high` — GPS-level precision for territory mapping.
  ///   - **Distance filter**: 5 meters — suppresses updates when the user
  ///     is stationary or moving very slowly, reducing battery drain and
  ///     unnecessary H3 cell calculations.
  ///
  /// The caller is responsible for listening to (and cancelling) the returned
  /// stream. Typically used by the journey feature during an active recording.
  Stream<Position> startTracking() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Only emit when the user moves ≥5 meters.
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cleanup
  // ─────────────────────────────────────────────────────────────────────────

  /// Cancels any active position stream subscription.
  ///
  /// Called automatically by Riverpod's `onDispose` callback when the
  /// [locationServiceProvider] is no longer in use.
  void dispose() {
    _subscription?.cancel();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Riverpod Provider
// ─────────────────────────────────────────────────────────────────────────────

/// Provides a singleton [LocationService] instance scoped to the app lifecycle.
///
/// When the provider is disposed (e.g., during hot-restart or app teardown),
/// it automatically calls [LocationService.dispose] to release native
/// platform resources.
final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(() => service.dispose());
  return service;
});
