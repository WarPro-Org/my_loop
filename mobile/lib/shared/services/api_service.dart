/// HTTP client service for communicating with the MyLoop .NET backend.
///
/// Wraps [Dio] to provide typed methods for each API endpoint: user
/// registration, territory queries, walk/claim submission, and
/// leaderboard retrieval. Exposed as a Riverpod provider for DI.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/shared/models/leaderboard_entry.dart';
import 'package:myloop/shared/models/user.dart';

/// Service class that encapsulates all HTTP communication with the backend.
///
/// Uses [Dio] with a configurable base URL (defaults to Android emulator
/// localhost). Each public method maps 1:1 to a backend API endpoint and
/// returns strongly-typed model objects.
class ApiService {
  final Dio _dio;

  ApiService({String? baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? 'http://192.168.1.8:5048',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

  /// Registers a new user account on the backend.
  ///
  /// Called after Firebase authentication and avatar selection. Returns
  /// the created [AppUser] with its server-generated ID.
  Future<AppUser> register({
    required String firebaseUid,
    required String displayName,
    required String color,
    required int avatarId,
  }) async {
    final response = await _dio.post('/api/users/register', data: {
      'firebaseUid': firebaseUid,
      'displayName': displayName,
      'color': color,
      'avatarId': avatarId,
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
  /// Returns a ranked list of [LeaderboardEntry] objects sorted by
  /// cell count descending.
  Future<List<LeaderboardEntry>> getLeaderboard({
    required double lat,
    required double lng,
    String? userId,
  }) async {
    final response = await _dio.get('/api/leaderboard', queryParameters: {
      'lat': lat,
      'lng': lng,
      if (userId case final uid?) 'userId': uid,
    });
    final data = response.data as Map<String, dynamic>;
    final list = data['top'] as List;
    return list.map((j) => LeaderboardEntry.fromJson(j as Map<String, dynamic>)).toList();
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
