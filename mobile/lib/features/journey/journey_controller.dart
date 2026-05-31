/// Journey controller — manages GPS tracking state during a walk.
///
/// Uses Riverpod's [Notifier] pattern to expose reactive [JourneyState].
/// Detects loops in real-time and fetches hex previews from the API.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myloop/shared/constants/app_constants.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/location_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/features/journey/loop_detector.dart';

// ──────────────────────────────────────────────────────────────────────────────
// State
// ──────────────────────────────────────────────────────────────────────────────

enum JourneyStatus { idle, tracking, submitting }

class JourneyState {
  final JourneyStatus status;
  final List<List<double>> path;
  final double distanceMeters;
  final Duration elapsed;
  final Position? currentPosition;
  final String? error;
  final List<List<List<double>>> previewBoundaries;
  final int loopCount;
  /// Hex boundaries claimed in real-time during this walk (walk-through claiming).
  final List<List<List<double>>> claimedHexBoundaries;
  /// Running count of hexes claimed this walk.
  final int claimedCount;
  /// Last stolen hex info for UI feedback.
  final String? lastStolenFrom;

  const JourneyState({
    this.status = JourneyStatus.idle,
    this.path = const [],
    this.distanceMeters = 0,
    this.elapsed = Duration.zero,
    this.currentPosition,
    this.error,
    this.previewBoundaries = const [],
    this.loopCount = 0,
    this.claimedHexBoundaries = const [],
    this.claimedCount = 0,
    this.lastStolenFrom,
  });

  JourneyState copyWith({
    JourneyStatus? status,
    List<List<double>>? path,
    double? distanceMeters,
    Duration? elapsed,
    Position? currentPosition,
    String? error,
    List<List<List<double>>>? previewBoundaries,
    int? loopCount,
    List<List<List<double>>>? claimedHexBoundaries,
    int? claimedCount,
    String? lastStolenFrom,
  }) {
    return JourneyState(
      status: status ?? this.status,
      path: path ?? this.path,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      elapsed: elapsed ?? this.elapsed,
      currentPosition: currentPosition ?? this.currentPosition,
      error: error,
      previewBoundaries: previewBoundaries ?? this.previewBoundaries,
      loopCount: loopCount ?? this.loopCount,
      claimedHexBoundaries: claimedHexBoundaries ?? this.claimedHexBoundaries,
      claimedCount: claimedCount ?? this.claimedCount,
      lastStolenFrom: lastStolenFrom ?? this.lastStolenFrom,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Controller
// ──────────────────────────────────────────────────────────────────────────────

class JourneyController extends Notifier<JourneyState> {
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  DateTime? _startTime;
  int _lastLoopCount = 0;
  bool _previewInFlight = false;
  int _pointsSinceLastCheck = 0;
  List<List<double>>? _pendingPreviewPath;

  static const int _loopCheckInterval = 5;

  @override
  JourneyState build() => const JourneyState();

  Future<void> startJourney() async {
    final locationService = ref.read(locationServiceProvider);

    try {
      final hasPermission = await locationService.requestPermission();
      if (!hasPermission) {
        state = state.copyWith(error: 'Location permission denied. Please allow location access.');
        return;
      }

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

      _positionSub = locationService.startTracking().listen(_onPosition);
      _startElapsedTimer();
    } catch (e) {
      state = state.copyWith(error: e.toString().replaceFirst('Exception: ', ''));
    }
  }

  List<List<double>> stopJourney() {
    _positionSub?.cancel();
    _timer?.cancel();
    _resetTrackingState();
    final path = state.path;
    state = state.copyWith(
      status: JourneyStatus.idle,
      path: const [],
      previewBoundaries: const [],
      claimedHexBoundaries: const [],
      claimedCount: 0,
    );
    return path;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // GPS position handling
  // ────────────────────────────────────────────────────────────────────────────

  void _onPosition(Position pos) {
    if (pos.accuracy > AppConstants.maxAccuracyMeters) {
      state = state.copyWith(currentPosition: pos);
      return;
    }

    final distanceFromLast = _distanceFromLastPoint(pos);
    final noiseFloor = _calculateNoiseFloor(pos);

    if (distanceFromLast < noiseFloor && state.path.isNotEmpty) {
      state = state.copyWith(currentPosition: pos);
      return;
    }

    final updatedPath = [...state.path, [pos.latitude, pos.longitude]];
    state = state.copyWith(
      path: updatedPath,
      currentPosition: pos,
      distanceMeters: state.distanceMeters + distanceFromLast,
    );

    _claimStep(pos.latitude, pos.longitude);
    _throttledLoopCheck(updatedPath);
  }

  double _distanceFromLastPoint(Position pos) {
    if (state.path.isEmpty) return 0;
    final last = state.path.last;
    return Geolocator.distanceBetween(last[0], last[1], pos.latitude, pos.longitude);
  }

  double _calculateNoiseFloor(Position pos) {
    if (state.path.isEmpty) return 0.0;

    final isStationary = pos.speed >= 0 && pos.speed < AppConstants.stationarySpeedThreshold;

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

  // ────────────────────────────────────────────────────────────────────────────
  // Real-time step claiming — claim each hex as user walks through it
  // ────────────────────────────────────────────────────────────────────────────

  bool _stepClaimInFlight = false;

  Future<void> _claimStep(double lat, double lng) async {
    if (_stepClaimInFlight) return; // Don't stack calls
    final userId = ref.read(userProfileProvider).userId;
    if (userId == null) return;

    _stepClaimInFlight = true;
    try {
      final api = ref.read(apiServiceProvider);
      final result = await api.claimStep(userId: userId, lat: lat, lng: lng);
      if (result != null && result.claimed && state.status == JourneyStatus.tracking) {
        final updatedBoundaries = [...state.claimedHexBoundaries, result.boundary];
        state = state.copyWith(
          claimedHexBoundaries: updatedBoundaries,
          claimedCount: state.claimedCount + 1,
          lastStolenFrom: result.wasStolen ? result.previousOwnerName : null,
        );
      }
    } catch (_) {
      // Best-effort — don't interrupt the walk
    } finally {
      _stepClaimInFlight = false;
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Loop detection & preview
  // ────────────────────────────────────────────────────────────────────────────

  void _throttledLoopCheck(List<List<double>> path) {
    _pointsSinceLastCheck++;
    if (_pointsSinceLastCheck < _loopCheckInterval) return;
    _pointsSinceLastCheck = 0;

    final loopCount = LoopDetector.countLoops(path);
    if (loopCount != _lastLoopCount) {
      _lastLoopCount = loopCount;
      state = state.copyWith(loopCount: loopCount);
      if (loopCount > 0) {
        _fetchPreview(List.from(path));
      }
    }
  }

  Future<void> _fetchPreview(List<List<double>> path) async {
    if (_previewInFlight) {
      _pendingPreviewPath = path;
      return;
    }
    _previewInFlight = true;
    _pendingPreviewPath = null;

    try {
      final api = ref.read(apiServiceProvider);
      // Cap path to avoid sending huge payloads — server enforces same limit
      final cappedPath = path.length > AppConstants.maxPreviewPathPoints
          ? path.sublist(path.length - AppConstants.maxPreviewPathPoints)
          : path;
      final boundaries = await api.previewClaim(path: cappedPath);
      if (boundaries.isNotEmpty && state.status == JourneyStatus.tracking) {
        state = state.copyWith(previewBoundaries: boundaries);
      }
    } catch (_) {
      // Preview is best-effort
    } finally {
      _previewInFlight = false;
      final pending = _pendingPreviewPath;
      if (pending != null) {
        _pendingPreviewPath = null;
        _fetchPreview(pending);
      }
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Utilities
  // ────────────────────────────────────────────────────────────────────────────

  void _startElapsedTimer() {
    _timer = Timer.periodic(
      const Duration(seconds: AppConstants.timerIntervalSeconds),
      (_) {
        if (_startTime != null) {
          state = state.copyWith(elapsed: DateTime.now().difference(_startTime!));
        }
      },
    );
  }

  void _resetTrackingState() {
    _lastLoopCount = 0;
    _previewInFlight = false;
    _pointsSinceLastCheck = 0;
    _pendingPreviewPath = null;
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Provider
// ──────────────────────────────────────────────────────────────────────────────

final journeyControllerProvider =
    NotifierProvider<JourneyController, JourneyState>(JourneyController.new);
