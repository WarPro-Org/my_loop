/// Journey screen — live map view for recording territory-capturing walks.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/features/journey/journey_controller.dart';
import 'package:myloop/features/journey/hex_overlay.dart';
import 'package:myloop/features/journey/hex_territory_manager.dart';
import 'package:myloop/features/journey/celebration_dialog.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/location_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/widgets/avatar_widget.dart';
import 'package:myloop/shared/widgets/big_button.dart';
import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/features/profile/user_profile_screen.dart';
import 'package:myloop/shared/constants/app_constants.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Screen
// ──────────────────────────────────────────────────────────────────────────────

class JourneyScreen extends ConsumerStatefulWidget {
  const JourneyScreen({super.key});

  @override
  ConsumerState<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends ConsumerState<JourneyScreen> {
  final _mapKey = GlobalKey<_JourneyMapState>();
  bool _isSubmitting = false;

  Future<void> _onStopCapture() async {
    if (_isSubmitting) return;

    final journey = ref.read(journeyControllerProvider);
    final controller = ref.read(journeyControllerProvider.notifier);
    final walkDistance = journey.distanceMeters;
    final walkDuration = journey.elapsed;
    final path = controller.stopJourney();

    if (path.length < 2) {
      _showSnackbar('Walk a bit more to capture territory!', Colors.orange);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _submitAndCelebrate(path, walkDistance, walkDuration);
    } catch (e) {
      _showSnackbar('Error: ${e.toString().replaceFirst('Exception: ', '')}', AppColors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitAndCelebrate(
      List<List<double>> path, double distance, Duration duration) async {
    final api = ref.read(apiServiceProvider);
    final profile = ref.read(userProfileProvider);
    if (profile.userId == null) return;

    final result = await api.submitClaim(userId: profile.userId!, path: path);
    final capturedCount = (result['cellCount'] as num?)?.toInt() ?? 0;
    final stolenCount = (result['stolenFromOthers'] as num?)?.toInt() ?? 0;

    _renderCapturedHexes(result);
    _optimisticHexUpdate(capturedCount);
    _mapKey.currentState?.forceReloadHexes();

    await _refreshUserData(profile, api);

    if (mounted) {
      await Future.delayed(const Duration(milliseconds: AppConstants.celebrationDelayMs));
      if (mounted) {
        final user = await api.getUser(profile.userId!);
        _showCelebration(capturedCount, stolenCount, distance, duration, user.streak);
      }
    }
  }

  void _renderCapturedHexes(Map<String, dynamic> result) {
    final rawBoundaries = result['boundaries'] as List<dynamic>?;
    if (rawBoundaries == null || rawBoundaries.isEmpty) return;

    final boundaries = rawBoundaries
        .map<List<List<double>>>((b) => (b as List<dynamic>)
            .map<List<double>>(
                (point) => (point as List<dynamic>).map<double>((v) => (v as num).toDouble()).toList())
            .toList())
        .toList();
    _mapKey.currentState?.showCapturedHexes(boundaries);
  }

  void _optimisticHexUpdate(int capturedCount) {
    if (!mounted || capturedCount <= 0) return;
    final profile = ref.read(userProfileProvider);
    ref.read(userProfileProvider.notifier).updateStats(hexCount: profile.hexCount + capturedCount);
  }

  Future<void> _refreshUserData(dynamic profile, ApiService api) async {
    final user = await api.getUser(profile.userId!);
    int updatedRank = profile.rank;
    try {
      final lb = await api.getLeaderboard(lat: 0, lng: 0, userId: profile.userId!, scope: 'city');
      updatedRank = lb.myRank ?? profile.rank;
    } catch (_) {}

    if (mounted) {
      ref.read(userProfileProvider.notifier).updateStats(
        hexCount: user.hexCount,
        streak: user.streak,
        distanceKm: user.distanceKm,
        rank: updatedRank,
      );
    }
  }

  void _showCelebration(int hexCount, int stolenCount, double distance, Duration duration, int streak) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CelebrationDialog(
        hexCount: hexCount,
        stolenCount: stolenCount,
        distanceMeters: distance,
        duration: duration,
        streak: streak,
      ),
    );
  }

  void _showSnackbar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final journey = ref.watch(journeyControllerProvider);
    final controller = ref.read(journeyControllerProvider.notifier);

    ref.listen(journeyControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        _showSnackbar(next.error!, AppColors.red);
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          _JourneyMap(key: _mapKey, journey: journey),
          _CloseButton(padding: MediaQuery.of(context).padding.top),
          if (journey.status == JourneyStatus.tracking)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              left: 0,
              child: _StatsBar(journey: journey, loopCount: journey.loopCount),
            ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _BottomControls(
              journey: journey,
              isSubmitting: _isSubmitting,
              onStartJourney: controller.startJourney,
              onStopCapture: _onStopCapture,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Close Button
// ──────────────────────────────────────────────────────────────────────────────

class _CloseButton extends StatelessWidget {
  final double padding;
  const _CloseButton({required this.padding});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: padding + 12,
      left: 16,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: const Icon(Icons.close, color: AppColors.dark, size: 22),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Map
// ──────────────────────────────────────────────────────────────────────────────

class _JourneyMap extends ConsumerStatefulWidget {
  final JourneyState journey;
  const _JourneyMap({super.key, required this.journey});

  @override
  ConsumerState<_JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends ConsumerState<_JourneyMap> {
  final MapController _mapController = MapController();
  Position? _initialPosition;
  LatLng? _fallbackCenter;
  Timer? _locationTimer;
  Timer? _hexRefreshTimer;
  bool _mapReady = false;
  bool _followUser = true;
  bool _locationError = false;
  double _currentZoom = 17.0;
  bool _useSatellite = true;
  bool _solidHexes = false;
  List<List<List<double>>> _capturedHexBoundaries = [];
  late HexTerritoryManager _hexManager;

  @override
  void initState() {
    super.initState();
    final api = ref.read(apiServiceProvider);
    final profile = ref.read(userProfileProvider);
    _hexManager = HexTerritoryManager(api: api, userId: profile.userId);
    _acquireLocation();
    _hexRefreshTimer = Timer.periodic(
      const Duration(seconds: AppConstants.hexRefreshIntervalSeconds),
      (_) => _refreshViewportHexes(),
    );
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _hexRefreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _acquireLocation() async {
    try {
      final locationService = ref.read(locationServiceProvider);
      await locationService.requestPermission();
      final pos = await locationService.getCurrentPosition();
      if (mounted && pos.latitude.isFinite && pos.longitude.isFinite) {
        setState(() { _initialPosition = pos; _locationError = false; });
        if (_mapReady && _followUser) {
          _mapController.move(LatLng(pos.latitude, pos.longitude), 17);
        }
        await _hexManager.loadUserOwnHexes();
        await _hexManager.loadWideArea(pos.latitude, pos.longitude);
        if (mounted) setState(() {});
      } else if (mounted) {
        setState(() => _locationError = true);
      }
    } catch (_) {
      if (mounted) setState(() => _locationError = true);
    }
  }

  Future<void> _refreshViewportHexes() async {
    if (!_mapReady) return;
    final bounds = _mapController.camera.visibleBounds;
    await _hexManager.loadViewport(
      minLat: bounds.south, minLng: bounds.west,
      maxLat: bounds.north, maxLng: bounds.east,
    );
    if (mounted) setState(() {});
  }

  Future<void> _refreshPosition() async {
    final journey = ref.read(journeyControllerProvider);
    if (journey.status == JourneyStatus.tracking) return;
    try {
      final locationService = ref.read(locationServiceProvider);
      final pos = await locationService.getCurrentPosition();
      if (mounted && pos.latitude.isFinite && pos.longitude.isFinite) {
        setState(() => _initialPosition = pos);
        if (_mapReady && _followUser) {
          _mapController.move(LatLng(pos.latitude, pos.longitude), _mapController.camera.zoom);
        }
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _JourneyMap old) {
    super.didUpdateWidget(old);
    _manageLocationPolling();
    _followCurrentPosition();
  }

  void _manageLocationPolling() {
    if (widget.journey.status == JourneyStatus.tracking && _locationTimer == null) {
      _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshPosition());
    } else if (widget.journey.status != JourneyStatus.tracking && _locationTimer != null) {
      _locationTimer?.cancel();
      _locationTimer = null;
    }
  }

  void _followCurrentPosition() {
    final pos = widget.journey.currentPosition;
    if (pos != null && _mapReady && _followUser && pos.latitude.isFinite && pos.longitude.isFinite) {
      _mapController.move(LatLng(pos.latitude, pos.longitude), _mapController.camera.zoom);
    }
  }

  void showCapturedHexes(List<List<List<double>>> boundaries) {
    setState(() {
      _capturedHexBoundaries = boundaries;
      _hexManager.addCapturedHexes(boundaries);
    });
  }

  void forceReloadHexes() {
    _hexManager.loadUserOwnHexes().then((_) {
      if (mounted) setState(() {});
    });
    if (_mapReady) {
      _refreshViewportHexes();
    } else if (_initialPosition != null) {
      _hexManager.loadWideArea(_initialPosition!.latitude, _initialPosition!.longitude).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _onMapTap(LatLng latLng) {
    final tappedCell = _findTappedCell(latLng.latitude, latLng.longitude);
    if (tappedCell != null) _showHexOwnerSheet(tappedCell);
  }

  TerritoryCell? _findTappedCell(double lat, double lng) {
    for (final cell in _hexManager.allCells) {
      if (_pointInPolygon(lat, lng, cell.boundary)) return cell;
    }
    return null;
  }

  static bool _pointInPolygon(double lat, double lng, List<List<double>> polygon) {
    var inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final yi = polygon[i][0], xi = polygon[i][1];
      final yj = polygon[j][0], xj = polygon[j][1];
      if (((yi > lat) != (yj > lat)) && (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }
    return inside;
  }

  void _showHexOwnerSheet(TerritoryCell cell) {
    final profile = ref.read(userProfileProvider);
    final isOwn = cell.ownerId == profile.userId;
    final ownerColor = Color(int.parse(cell.ownerColor.replaceFirst('#', ''), radix: 16) | 0xFF000000);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _HexOwnerSheet(
        cell: cell,
        isOwn: isOwn,
        ownerColor: ownerColor,
        onViewProfile: () {
          Navigator.pop(ctx);
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => UserProfileScreen(
              userId: cell.ownerId,
              name: cell.ownerName,
              avatarId: 0,
              color: cell.ownerColor,
              rank: 0,
            ),
          ));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final journey = widget.journey;
    final profile = ref.watch(userProfileProvider);
    final userColor = Color(int.parse(profile.color.replaceFirst('#', ''), radix: 16) | 0xFF000000);

    if (_initialPosition == null && _fallbackCenter == null && journey.currentPosition == null) {
      return _buildLoadingState();
    }

    final center = _resolveCenter(journey);

    return Stack(
      children: [
        _buildMap(center, journey, profile, userColor),
        if (!_followUser) _buildRecenterButton(),
        _buildTopRightControls(context, profile, userColor),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_locationError) ...[
            const Icon(Icons.location_off, size: 48, color: AppColors.grey),
            const SizedBox(height: 12),
            const Text('Could not get your location', style: TextStyle(color: AppColors.grey)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () { setState(() => _locationError = false); _acquireLocation(); },
              child: const Text('Retry'),
            ),
          ] else ...[
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            const Text('Getting your location...', style: TextStyle(color: AppColors.grey)),
          ],
        ],
      ),
    );
  }

  LatLng _resolveCenter(JourneyState journey) {
    if (journey.currentPosition != null) {
      return LatLng(journey.currentPosition!.latitude, journey.currentPosition!.longitude);
    }
    if (_initialPosition != null) {
      return LatLng(_initialPosition!.latitude, _initialPosition!.longitude);
    }
    return _fallbackCenter!;
  }

  Widget _buildMap(LatLng center, JourneyState journey, dynamic profile, Color userColor) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 17,
        onMapReady: () {
          _mapReady = true;
          final target = _initialPosition != null
              ? LatLng(_initialPosition!.latitude, _initialPosition!.longitude)
              : _fallbackCenter;
          if (target != null) _mapController.move(target, 17);
        },
        onPositionChanged: (pos, hasGesture) {
          if (pos.zoom != _currentZoom) setState(() => _currentZoom = pos.zoom);
          if (hasGesture && _followUser) setState(() => _followUser = false);
        },
        onTap: (tapPos, latLng) => _onMapTap(latLng),
      ),
      children: [
        _buildTileLayer(),
        if (_useSatellite) _buildLabelsLayer(),
        ..._buildOtherPlayerHexes(),
        if (_hexManager.userOwnHexBoundaries.isNotEmpty)
          AnimatedHexOverlay(
            hexBoundaries: _hexManager.userOwnHexBoundaries,
            userColor: userColor,
            currentZoom: _currentZoom,
            solidMode: _solidHexes,
          ),
        if (journey.previewBoundaries.isNotEmpty)
          AnimatedHexOverlay(
            hexBoundaries: journey.previewBoundaries,
            userColor: userColor.withAlpha(140),
            currentZoom: _currentZoom,
            isNewCapture: true,
            solidMode: false,
          ),
        if (_capturedHexBoundaries.isNotEmpty)
          AnimatedHexOverlay(
            hexBoundaries: _capturedHexBoundaries,
            userColor: userColor,
            currentZoom: _currentZoom,
            isNewCapture: true,
            solidMode: _solidHexes,
          ),
        if (journey.path.length > 1) _buildPathPolyline(journey),
        if (_currentZoom >= 15) _buildCooldownMarkers(),
        _buildPositionMarker(journey, profile, userColor),
      ],
    );
  }

  MarkerLayer _buildCooldownMarkers() {
    final frozenCells = _hexManager.allCells
        .where((c) => c.isOnCooldown)
        .toList();

    return MarkerLayer(
      markers: frozenCells.map((cell) {
        final center = _cellCenter(cell.boundary);
        final remaining = cell.cooldownRemaining;
        final label = remaining.inMinutes >= 60
            ? '${remaining.inHours}h${remaining.inMinutes % 60}m'
            : '${remaining.inMinutes}m';

        return Marker(
          point: LatLng(center[0], center[1]),
          width: 48,
          height: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield, color: Color(0xFF64B5F6), size: 10),
                const SizedBox(width: 2),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  List<double> _cellCenter(List<List<double>> boundary) {
    if (boundary.isEmpty) return [0, 0];
    double lat = 0, lng = 0;
    for (final p in boundary) {
      lat += p[0];
      lng += p[1];
    }
    return [lat / boundary.length, lng / boundary.length];
  }

  TileLayer _buildTileLayer() {
    return TileLayer(
      urlTemplate: _useSatellite
          ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
          : 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
      subdomains: _useSatellite ? const [] : const ['a', 'b', 'c', 'd'],
      userAgentPackageName: 'com.myloop.app',
    );
  }

  TileLayer _buildLabelsLayer() {
    return TileLayer(
      urlTemplate: 'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
      userAgentPackageName: 'com.myloop.app',
    );
  }

  List<Widget> _buildOtherPlayerHexes() {
    return _hexManager.otherHexesByColor.entries.map((entry) => AnimatedHexOverlay(
      hexBoundaries: entry.value,
      userColor: Color(int.parse(entry.key.replaceFirst('#', ''), radix: 16) | 0xFF000000),
      currentZoom: _currentZoom,
      isNewCapture: false,
      solidMode: _solidHexes,
    )).toList();
  }

  PolylineLayer _buildPathPolyline(JourneyState journey) {
    return PolylineLayer(
      polylines: [
        Polyline(
          points: journey.path.map((p) => LatLng(p[0], p[1])).toList(),
          color: AppColors.primary,
          strokeWidth: 4,
        ),
      ],
    );
  }

  MarkerLayer _buildPositionMarker(JourneyState journey, dynamic profile, Color userColor) {
    final point = journey.currentPosition != null
        ? LatLng(journey.currentPosition!.latitude, journey.currentPosition!.longitude)
        : _initialPosition != null
            ? LatLng(_initialPosition!.latitude, _initialPosition!.longitude)
            : _fallbackCenter!;

    return MarkerLayer(
      markers: [
        Marker(
          point: point, width: 44, height: 44,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.white, width: 3),
              boxShadow: [BoxShadow(color: userColor.withValues(alpha: 0.4), blurRadius: 10, spreadRadius: 3)],
            ),
            child: ClipOval(child: AvatarWidget(avatarId: profile.avatarId, color: profile.color, size: 38)),
          ),
        ),
      ],
    );
  }

  Widget _buildRecenterButton() {
    return Positioned(
      bottom: 140, right: 16,
      child: GestureDetector(
        onTap: () {
          setState(() => _followUser = true);
          final pos = widget.journey.currentPosition ?? _initialPosition;
          if (pos != null && _mapReady) {
            _mapController.move(LatLng(pos.latitude, pos.longitude), _mapController.camera.zoom);
          }
        },
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.white, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: const Icon(Icons.my_location, color: AppColors.primary, size: 24),
        ),
      ),
    );
  }

  Widget _buildTopRightControls(BuildContext context, dynamic profile, Color userColor) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      right: 16,
      child: Column(
        children: [
          _CircleButton(
            icon: _useSatellite ? Icons.dark_mode : Icons.satellite_alt,
            onTap: () => setState(() => _useSatellite = !_useSatellite),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hexagon, color: userColor, size: 18),
                const SizedBox(width: 4),
                Text('${profile.hexCount}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.dark)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _CircleButton(
            icon: _solidHexes ? Icons.visibility_off : Icons.visibility,
            color: _solidHexes ? userColor : AppColors.white,
            iconColor: _solidHexes ? AppColors.white : AppColors.dark,
            onTap: () => setState(() => _solidHexes = !_solidHexes),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ──────────────────────────────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color iconColor;

  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.color = AppColors.white,
    this.iconColor = AppColors.dark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: color, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }
}

class _HexOwnerSheet extends StatelessWidget {
  final TerritoryCell cell;
  final bool isOwn;
  final Color ownerColor;
  final VoidCallback onViewProfile;

  const _HexOwnerSheet({
    required this.cell,
    required this.isOwn,
    required this.ownerColor,
    required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.greyLight, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: ownerColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ownerColor, width: 2),
                ),
                child: const Icon(Icons.hexagon, size: 28, color: Colors.white70),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOwn ? 'Your Hex' : '${cell.ownerName}\'s Hex',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                    Text(
                      isOwn ? 'You own this territory' : 'Owned by ${cell.ownerName}',
                      style: TextStyle(color: AppColors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (cell.isOnCooldown) ...[
            const SizedBox(height: 16),
            _CooldownBanner(cell: cell),
          ],
          if (!isOwn) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onViewProfile,
                icon: const Icon(Icons.person, size: 18),
                label: Text('View ${cell.ownerName}\'s Profile'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CooldownBanner extends StatelessWidget {
  final TerritoryCell cell;
  const _CooldownBanner({required this.cell});

  @override
  Widget build(BuildContext context) {
    final remaining = cell.cooldownRemaining;
    final text = remaining.inMinutes >= 60
        ? '${remaining.inHours}h ${remaining.inMinutes % 60}m'
        : '${remaining.inMinutes}m';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2196F3).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield, color: Color(0xFF2196F3), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Protected — $text remaining',
              style: const TextStyle(
                color: Color(0xFF2196F3),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Stats & Controls
// ──────────────────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final JourneyState journey;
  final int loopCount;
  const _StatsBar({required this.journey, this.loopCount = 0});

  @override
  Widget build(BuildContext context) {
    final minutes = journey.elapsed.inMinutes;
    final seconds = journey.elapsed.inSeconds % 60;
    final distanceKm = journey.distanceMeters / 1000;

    return Container(
      margin: const EdgeInsets.only(left: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Table(
        columnWidths: const { 0: FixedColumnWidth(24), 1: IntrinsicColumnWidth() },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          _statRow(Icons.schedule_rounded, const Color(0xFF00D4AA),
            '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'),
          _spacerRow(),
          _statRow(Icons.route_rounded, const Color(0xFF6C5CE7),
            distanceKm >= 1 ? '${distanceKm.toStringAsFixed(2)} km' : '${journey.distanceMeters.toInt()} m'),
          _spacerRow(),
          _statRow(Icons.loop_rounded, const Color(0xFFF59E0B),
            loopCount > 0 ? '$loopCount loop${loopCount > 1 ? 's' : ''}' : 'No loop'),
        ],
      ),
    );
  }

  TableRow _statRow(IconData icon, Color color, String value) {
    return TableRow(children: [
      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Center(child: Icon(icon, size: 18, color: color))),
      Padding(
        padding: const EdgeInsets.only(left: 10, top: 6, bottom: 6),
        child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
      ),
    ]);
  }

  TableRow _spacerRow() {
    return TableRow(children: [
      const SizedBox(height: 1),
      Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
    ]);
  }
}

class _BottomControls extends StatelessWidget {
  final JourneyState journey;
  final bool isSubmitting;
  final VoidCallback onStartJourney;
  final VoidCallback onStopCapture;

  const _BottomControls({
    required this.journey,
    required this.isSubmitting,
    required this.onStartJourney,
    required this.onStopCapture,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))],
        ),
        child: journey.status == JourneyStatus.tracking
            ? _buildTrackingControls()
            : _buildIdleControls(),
      ),
    );
  }

  Widget _buildIdleControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🚶 Ready to capture territory?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Walk a loop to claim hexagons!', style: TextStyle(fontSize: 13, color: AppColors.grey)),
        const SizedBox(height: 16),
        BigButton(label: 'START JOURNEY', icon: Icons.play_arrow, onPressed: onStartJourney),
      ],
    );
  }

  Widget _buildTrackingControls() {
    final hasLoop = journey.loopCount > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          hasLoop ? '✅ ${journey.loopCount} loop${journey.loopCount > 1 ? 's' : ''} detected!' : '🔴 Recording your path...',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          hasLoop ? 'Ready to capture! Or keep walking for more loops.' : 'Walk back near your path to close a loop.',
          style: TextStyle(fontSize: 13, color: AppColors.grey),
        ),
        const SizedBox(height: 16),
        BigButton(
          label: isSubmitting ? 'SUBMITTING...' : 'STOP & CAPTURE',
          icon: isSubmitting ? Icons.hourglass_empty : Icons.stop,
          color: hasLoop ? AppColors.primary : AppColors.grey,
          onPressed: isSubmitting || !hasLoop ? null : onStopCapture,
        ),
        if (!hasLoop)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Close a loop to enable capture',
              style: TextStyle(fontSize: 11, color: AppColors.grey.withValues(alpha: 0.7)),
            ),
          ),
      ],
    );
  }
}
