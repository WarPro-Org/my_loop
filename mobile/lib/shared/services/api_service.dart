import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/shared/models/leaderboard_entry.dart';
import 'package:myloop/shared/models/user.dart';

// API client for talking to the .NET backend
class ApiService {
  final Dio _dio;

  ApiService({String? baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? 'http://10.0.2.2:5048', // Android emulator localhost
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

  // Register a new user
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

  // Get territories in a bounding box (for map display)
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

  // Submit a completed walk/claim
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

  // Get leaderboard
  Future<List<LeaderboardEntry>> getLeaderboard({
    required double lat,
    required double lng,
  }) async {
    final response = await _dio.get('/api/leaderboard', queryParameters: {
      'lat': lat,
      'lng': lng,
    });
    final list = response.data as List;
    return list.map((j) => LeaderboardEntry.fromJson(j)).toList();
  }
}

// Riverpod provider for ApiService (single instance across the app)
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});
