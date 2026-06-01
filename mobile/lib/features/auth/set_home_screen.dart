/// Set Home Location screen — shown during onboarding after registration.
///
/// Gets the user's current GPS position and asks them to confirm it
/// as their home location (used for decay calculations).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/widgets/big_button.dart';

class SetHomeScreen extends ConsumerStatefulWidget {
  const SetHomeScreen({super.key});

  @override
  ConsumerState<SetHomeScreen> createState() => _SetHomeScreenState();
}

class _SetHomeScreenState extends ConsumerState<SetHomeScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  Position? _position;
  Map<String, dynamic>? _homeResult;

  @override
  void initState() {
    super.initState();
    _detectLocation();
  }

  Future<void> _detectLocation() async {
    try {
      // Check/request permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _error = 'Location permission is required to set your home area.';
          _loading = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      setState(() {
        _position = position;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not get location: $e';
        _loading = false;
      });
    }
  }

  Future<void> _confirmHome() async {
    if (_position == null) return;
    setState(() => _submitting = true);

    try {
      final userId = ref.read(userProfileProvider).userId;
      if (userId == null) throw Exception('No user ID');

      final api = ref.read(apiServiceProvider);
      final result = await api.setHome(
        userId: userId,
        lat: _position!.latitude,
        lng: _position!.longitude,
      );

      setState(() {
        _homeResult = result;
        _submitting = false;
      });

      // Brief delay to show the resolved location, then navigate
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() {
        _error = 'Failed to set home: $e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkHard,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.home_rounded, size: 72, color: AppColors.primary),
              const SizedBox(height: 24),
              Text(
                'Set Your Home',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your home location determines how long your territory lasts when you travel far away. Hexes near home decay in 7 days, while hexes in other cities or countries last much longer.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.white.withValues(alpha: 0.7), fontSize: 14),
              ),
              const SizedBox(height: 32),
              if (_loading) ...[
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: 16),
                Text(
                  'Detecting your location...',
                  style: TextStyle(color: AppColors.white.withValues(alpha: 0.6)),
                ),
              ] else if (_error != null) ...[
                Icon(Icons.error_outline, size: 48, color: AppColors.red.withValues(alpha: 0.8)),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.red, fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _detectLocation();
                  },
                  child: const Text('Retry', style: TextStyle(color: AppColors.primary)),
                ),
              ] else if (_position != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.dark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.location_on, color: AppColors.primary, size: 32),
                      const SizedBox(height: 8),
                      if (_homeResult != null) ...[
                        Text(
                          '${_homeResult!['homeCity'] ?? ''}, ${_homeResult!['homeState'] ?? ''}',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _homeResult!['homeCountry'] ?? '',
                          style: TextStyle(
                            color: AppColors.white.withValues(alpha: 0.6),
                            fontSize: 14,
                          ),
                        ),
                      ] else ...[
                        Text(
                          'Your current location',
                          style: TextStyle(
                            color: AppColors.white.withValues(alpha: 0.8),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_position!.latitude.toStringAsFixed(4)}, ${_position!.longitude.toStringAsFixed(4)}',
                          style: TextStyle(
                            color: AppColors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                BigButton(
                  label: _submitting ? 'Setting home...' : 'Confirm as Home',
                  onPressed: _submitting ? null : _confirmHome,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    // Skip for now — user can set later in settings
                    context.go('/home');
                  },
                  child: Text(
                    'Skip for now',
                    style: TextStyle(color: AppColors.white.withValues(alpha: 0.4)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
