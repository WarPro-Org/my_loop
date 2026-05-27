import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myloop/shared/services/location_service.dart';

// Tracks the journey state: recording path, distance, duration
enum JourneyStatus { idle, tracking, submitting }

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

// Controller that manages GPS tracking during a journey
class JourneyController extends Notifier<JourneyState> {
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  DateTime? _startTime;

  @override
  JourneyState build() => const JourneyState();

  // Start recording the walk
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
      state = state.copyWith(error: 'Could not get location: $e');
    }
  }

  // Called every time GPS gives us a new position
  void _onPosition(Position pos) {
    final newPoint = [pos.latitude, pos.longitude];
    final updatedPath = [...state.path, newPoint];

    // Calculate distance from last point
    double addedDistance = 0;
    if (state.path.isNotEmpty) {
      final last = state.path.last;
      addedDistance = Geolocator.distanceBetween(
        last[0], last[1], pos.latitude, pos.longitude,
      );
    }

    state = state.copyWith(
      path: updatedPath,
      currentPosition: pos,
      distanceMeters: state.distanceMeters + addedDistance,
    );
  }

  // Stop the journey and return the path for submission
  List<List<double>> stopJourney() {
    _positionSub?.cancel();
    _timer?.cancel();
    final path = state.path;
    state = state.copyWith(status: JourneyStatus.idle);
    return path;
  }
}

// Riverpod provider for the journey controller
final journeyControllerProvider =
    NotifierProvider<JourneyController, JourneyState>(JourneyController.new);
