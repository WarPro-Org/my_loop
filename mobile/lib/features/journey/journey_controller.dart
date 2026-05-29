/// Journey controller — manages GPS tracking state during a walk.
///
/// Uses Riverpod's [Notifier] pattern to expose reactive [JourneyState]
/// which includes the tracking status, GPS path, distance, elapsed time,
/// and any error messages. Integrates with [LocationService] for position
/// updates.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myloop/shared/services/location_service.dart';

/// The possible states of a journey recording session.
enum JourneyStatus { idle, tracking, submitting }

/// Immutable snapshot of the current journey state.
///
/// Contains the tracking status, recorded GPS path, calculated distance,
/// elapsed timer, current position, and any error to display to the user.
class JourneyState {
  final JourneyStatus status;
  final List<List<double>> path; // [[lat, lng], ...]
  final double distanceMeters;
  final Duration elapsed;
  final Position? currentPosition;
  final String? error; // shows error message to user

  const JourneyState({
    this.status = JourneyStatus.idle,
    this.path = const [],
    this.distanceMeters = 0,
    this.elapsed = Duration.zero,
    this.currentPosition,
    this.error,
  });

  /// Creates a copy of this state with optional field overrides.
  ///
  /// Setting [error] to `null` explicitly clears any previous error message.
  JourneyState copyWith({
    JourneyStatus? status,
    List<List<double>>? path,
    double? distanceMeters,
    Duration? elapsed,
    Position? currentPosition,
    String? error,
  }) {
    return JourneyState(
      status: status ?? this.status,
      path: path ?? this.path,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      elapsed: elapsed ?? this.elapsed,
      currentPosition: currentPosition ?? this.currentPosition,
      error: error,
    );
  }
}

/// Riverpod notifier that orchestrates GPS tracking during a journey.
///
/// Manages the lifecycle: request permissions → start listening to GPS
/// → accumulate path points → calculate distance → stop and return path.
/// Also runs a 1-second timer for elapsed time display.
class JourneyController extends Notifier<JourneyState> {
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  DateTime? _startTime;

  @override
  JourneyState build() => const JourneyState();

  /// Begins recording a new journey.
  ///
  /// Requests location permission, gets the initial position, then starts
  /// a GPS position stream and an elapsed-time timer. Updates [JourneyState]
  /// reactively on each new position or timer tick.
  Future<void> startJourney() async {
    final locationService = ref.read(locationServiceProvider);

    try {
      final hasPermission = await locationService.requestPermission();
      if (!hasPermission) {
        state = state.copyWith(error: 'Location permission denied. Please allow location access.');
        return;
      }

      // Get initial position
      final pos = await locationService.getCurrentPosition();
      _startTime = DateTime.now();

      state = state.copyWith(
        status: JourneyStatus.tracking,
        path: [[pos.latitude, pos.longitude]],
        currentPosition: pos,
        distanceMeters: 0,
        elapsed: Duration.zero,
        error: null,
      );

      // Start listening to position updates
      _positionSub = locationService.startTracking().listen(_onPosition);

      // Start elapsed timer (updates every second)
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_startTime != null) {
          state = state.copyWith(
            elapsed: DateTime.now().difference(_startTime!),
          );
        }
      });
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(error: msg);
    }
  }

  /// Handles each GPS position update from the location stream.
  ///
  /// Filters out GPS jitter by requiring movement to exceed the noise floor
  /// (determined by the position's reported accuracy). Only positions that
  /// represent genuine movement get recorded to the path and added to distance.
  /// The live marker (currentPosition) is always updated for visual feedback.
  void _onPosition(Position pos) {
    // Reject unreliable readings — accuracy > 25m means GPS is guessing
    if (pos.accuracy > 25.0) {
      state = state.copyWith(currentPosition: pos);
      return;
    }

    // Calculate distance from last accepted point
    double addedDistance = 0;
    if (state.path.isNotEmpty) {
      final last = state.path.last;
      addedDistance = Geolocator.distanceBetween(
        last[0], last[1], pos.latitude, pos.longitude,
      );
    }

    // Only accept the point if movement exceeds the noise floor.
    // The noise floor is the reported accuracy clamped to [8, 25] meters.
    // This prevents GPS jitter from accumulating false distance when stationary.
    // Additional check: if reported speed is available and essentially zero,
    // require even more displacement to accept the point.
    final noiseFloor = state.path.isEmpty
        ? 0.0
        : (pos.speed >= 0 && pos.speed < 0.3)
            ? pos.accuracy.clamp(10.0, 25.0) // Stationary: stricter filter
            : pos.accuracy.clamp(6.0, 20.0); // Moving: more permissive

    if (addedDistance < noiseFloor && state.path.isNotEmpty) {
      // Within noise range — update live marker only, don't record to path
      state = state.copyWith(currentPosition: pos);
      return;
    }

    // Valid movement detected — record the point and accumulate distance
    final newPoint = [pos.latitude, pos.longitude];
    final updatedPath = [...state.path, newPoint];

    state = state.copyWith(
      path: updatedPath,
      currentPosition: pos,
      distanceMeters: state.distanceMeters + addedDistance,
    );
  }

  /// Stops the journey, cancels subscriptions, and returns the recorded path.
  ///
  /// The returned path (list of `[lat, lng]` pairs) is used by the UI to
  /// submit the claim to the backend API.
  List<List<double>> stopJourney() {
    _positionSub?.cancel();
    _timer?.cancel();
    final path = state.path;
    state = state.copyWith(status: JourneyStatus.idle);
    return path;
  }
}

/// Riverpod provider for the [JourneyController].
///
/// Widgets watch this to react to journey state changes (tracking status,
/// path updates, errors).
final journeyControllerProvider =
    NotifierProvider<JourneyController, JourneyState>(JourneyController.new);
