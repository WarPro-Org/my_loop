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
import 'package:myloop/shared/constants/app_constants.dart';
import 'package:myloop/shared/services/location_service.dart';

/// The possible states of a journey recording session.
enum JourneyStatus { idle, tracking, submitting }

/// Immutable snapshot of the current journey state.
class JourneyState {
  final JourneyStatus status;
  final List<List<double>> path; // [[lat, lng], ...]
  final double distanceMeters;
  final Duration elapsed;
  final Position? currentPosition;
  final String? error;

  const JourneyState({
    this.status = JourneyStatus.idle,
    this.path = const [],
    this.distanceMeters = 0,
    this.elapsed = Duration.zero,
    this.currentPosition,
    this.error,
  });

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
class JourneyController extends Notifier<JourneyState> {
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  DateTime? _startTime;

  @override
  JourneyState build() => const JourneyState();

  /// Begins recording a new journey.
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

      // Start elapsed timer (ticks every second)
      _timer = Timer.periodic(
        const Duration(seconds: AppConstants.timerIntervalSeconds),
        (_) {
          if (_startTime != null) {
            state = state.copyWith(elapsed: DateTime.now().difference(_startTime!));
          }
        },
      );
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(error: msg);
    }
  }

  /// Handles each GPS position update from the location stream.
  ///
  /// Filters out GPS jitter using accuracy thresholds and speed-aware
  /// noise floors. Only genuine movement gets recorded to the path.
  void _onPosition(Position pos) {
    // Reject unreliable readings (accuracy worse than 25m)
    if (pos.accuracy > AppConstants.maxAccuracyMeters) {
      state = state.copyWith(currentPosition: pos);
      return;
    }

    // Calculate distance from last accepted point
    double distanceFromLast = 0;
    if (state.path.isNotEmpty) {
      final last = state.path.last;
      distanceFromLast = Geolocator.distanceBetween(
        last[0], last[1], pos.latitude, pos.longitude,
      );
    }

    // Determine noise floor based on movement speed.
    // Stationary (speed < 0.3 m/s): stricter threshold (10-25m)
    // Moving: more permissive (6-20m)
    final noiseFloor = _calculateNoiseFloor(pos);

    if (distanceFromLast < noiseFloor && state.path.isNotEmpty) {
      // Within noise range — update live marker only, skip recording
      state = state.copyWith(currentPosition: pos);
      return;
    }

    // Valid movement — record the point and add to distance
    final newPoint = [pos.latitude, pos.longitude];
    final updatedPath = [...state.path, newPoint];

    state = state.copyWith(
      path: updatedPath,
      currentPosition: pos,
      distanceMeters: state.distanceMeters + distanceFromLast,
    );
  }

  /// Calculates the GPS noise floor based on speed and accuracy.
  double _calculateNoiseFloor(Position pos) {
    if (state.path.isEmpty) return 0.0;

    final bool isStationary = pos.speed >= 0 && pos.speed < AppConstants.stationarySpeedThreshold;

    if (isStationary) {
      return pos.accuracy.clamp(
        AppConstants.stationaryNoiseFloorMin,
        AppConstants.stationaryNoiseFloorMax,
      );
    }

    return pos.accuracy.clamp(
      AppConstants.movingNoiseFloorMin,
      AppConstants.movingNoiseFloorMax,
    );
  }

  /// Stops the journey and returns the recorded path.
  List<List<double>> stopJourney() {
    _positionSub?.cancel();
    _timer?.cancel();
    final path = state.path;
    state = state.copyWith(status: JourneyStatus.idle, path: const []);
    return path;
  }
}

/// Riverpod provider for the [JourneyController].
final journeyControllerProvider =
    NotifierProvider<JourneyController, JourneyState>(JourneyController.new);
