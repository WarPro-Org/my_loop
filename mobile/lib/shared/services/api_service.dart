/// HTTP client service for communicating with the MyLoop .NET backend.
///
/// Wraps [Dio] to provide typed methods for each API endpoint: user
/// registration, territory queries, walk/claim submission, and
/// leaderboard retrieval. Exposed as a Riverpod provider for DI.
library;

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/shared/models/leaderboard_entry.dart';
import 'package:myloop/shared/models/user.dart';

/// The API base URL, configurable via --dart-define=API_URL=https://your-ngrok.ngrok-free.app
/// Defaults to ngrok tunnel for mobile testing over cellular.
const _defaultApiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://destitute-living-bullpen.ngrok-free.dev',
);

/// Service class that encapsulates all HTTP communication with the backend.
///
/// Uses [Dio] with a configurable base URL (defaults to Android emulator
/// localhost). Each public method maps 1:1 to a backend API endpoint and
/// returns strongly-typed model objects.
class ApiService {
  final Dio _dio;

  ApiService({String? baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? _defaultApiUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final token = await user.getIdToken();
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  /// Registers a new user account on the backend.
  ///
  /// Called after Firebase authentication and avatar selection. Returns
  /// the created [AppUser] with its server-generated ID.
  Future<AppUser> register({
    required String firebaseUid,
    required String displayName,
    required String color,
    required int avatarId,
    String authProvider = 'local',
  }) async {
    final response = await _dio.post('/api/users/register', data: {
      'firebaseUid': firebaseUid,
      'displayName': displayName,
      'color': color,
      'avatarId': avatarId,
      'authProvider': authProvider,
    });
    return AppUser.fromJson(response.data);
  }

  /// Fetches all territory cells within a geographic bounding box.
  ///
  /// Used to populate the map view with colored hexagons showing which
  /// players own which cells in the visible area.
  Future<List<TerritoryCell>> getTerritories({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
  }) async {
    final response = await _dio.get('/api/territories', queryParameters: {
      'minLat': minLat,
      'minLng': minLng,
      'maxLat': maxLat,
      'maxLng': maxLng,
    });
    final list = response.data as List;
    return list.map((j) => TerritoryCell.fromJson(j)).toList();
  }

  /// Returns ALL territory cells owned by [userId], regardless of viewport.
  /// Used to ensure the user's hexes always render on the map.
  Future<List<TerritoryCell>> getUserTerritories(String userId) async {
    final response = await _dio.get('/api/territories/user/$userId');
    final list = response.data as List;
    return list.map((j) => TerritoryCell.fromJson(j)).toList();
  }

  /// Returns a user's full claim history (one entry per walk submission).
  /// Used for the Hex History section on the home page.
  Future<List<Map<String, dynamic>>> getClaimHistory(String userId) async {
    final response = await _dio.get('/api/territories/claims/$userId');
    final list = response.data as List;
    return list.map((j) => j as Map<String, dynamic>).toList();
  }

  /// Submits a completed walk path to the backend for territory claiming.
  ///
  /// The backend runs H3 hex resolution, loop detection, and territory
  /// assignment. Returns a result map with captured cell count and details.
  Future<Map<String, dynamic>> submitClaim({
    required String userId,
    required List<List<double>> path,
  }) async {
    final response = await _dio.post('/api/claims', data: {
      'userId': userId,
      'path': path,
    });
    return response.data as Map<String, dynamic>;
  }

  /// Retrieves the leaderboard for players near the given coordinates.
  ///
  /// [scope] can be "local", "city", or "country".
  /// Returns a ranked list of [LeaderboardEntry] objects sorted by
  /// cell count descending, plus the logged-in user's rank.
  Future<LeaderboardResponse> getLeaderboard({
    required double lat,
    required double lng,
    String? userId,
    String scope = 'local',
  }) async {
    final response = await _dio.get('/api/leaderboard', queryParameters: {
      'lat': lat,
      'lng': lng,
      if (userId case final uid?) 'userId': uid,
      'scope': scope,
    });
    final data = response.data as Map<String, dynamic>;
    return LeaderboardResponse.fromJson(data);
  }

  /// Fetches a user's profile by ID.
  Future<AppUser> getUser(String id) async {
    final response = await _dio.get('/api/users/$id');
    return AppUser.fromJson(response.data);
  }

  /// Looks up a user by Firebase UID. Returns null if not registered.
  Future<AppUser?> getUserByUid(String firebaseUid) async {
    try {
      final response = await _dio.get('/api/users/by-uid/$firebaseUid');
      return AppUser.fromJson(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Fetches a user's rich public profile (rank, top 3 finishes, max streak, etc.)
  Future<Map<String, dynamic>> getUserProfile(String id) async {
    final response = await _dio.get('/api/users/$id/profile');
    return response.data as Map<String, dynamic>;
  }
}

/// Riverpod provider exposing a singleton [ApiService] instance.
///
/// Inject via `ref.read(apiServiceProvider)` to access the API client
/// from any widget or controller.
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});
