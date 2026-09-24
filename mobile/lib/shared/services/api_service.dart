/// HTTP client service for communicating with the MyLoop .NET backend.
///
/// Wraps [Dio] to provide typed methods for each API endpoint: user
/// registration, territory queries, walk/claim submission, and
/// leaderboard retrieval. Exposed as a Riverpod provider for DI.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/constants/app_constants.dart';
import 'package:myloop/shared/models/exploration_neighborhood.dart';
import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/shared/models/leaderboard_entry.dart';
import 'package:myloop/shared/models/daily_mission.dart';
import 'package:myloop/shared/models/achievement.dart';
import 'package:myloop/shared/models/user.dart';
import 'package:logging/logging.dart';
import 'package:myloop/shared/services/batch_drain_service.dart';
import 'package:myloop/shared/services/mock/mock_walk_config.dart';
import 'package:myloop/shared/services/step_claim_queue.dart';
import 'package:myloop/shared/services/trace_context.dart';
import 'package:myloop/shared/util/local_day.dart';

final _log = Logger('API');

/// Anonymous liveness endpoint on the backend (`HealthController`). Used by the
/// reachability probe — no auth, cheap, safe to hit before every journey start.
const _healthCheckPath = '/';

/// Build-time API host, supplied as `--dart-define=API_URL=https://your-host`.
const _apiUrlFromEnvironment = String.fromEnvironment('API_URL');

/// Fallback for **debug builds only**, so `flutter run` needs no extra flags.
///
/// Deliberately not used in release or profile. A default baked into a built
/// binary keeps being called by every installed copy forever, and this host is a
/// reclaimable ngrok subdomain — if it lapses, whoever registers it next
/// receives real users' Firebase JWTs and GPS coordinates (#139 D8).
const _devFallbackApiUrl = 'https://destitute-living-bullpen.ngrok-free.dev';

/// Resolves the API host, returning an empty string when a non-debug build has
/// no `API_URL`. Callers must treat empty as fatal — see [apiBaseUrlConfigError].
///
/// Gated on **debug**, not on "not release": `kReleaseMode` is `false` in profile
/// mode, so keying off it would let a profile build silently use the dev tunnel.
/// Profile builds run on real devices over real networks, so they get the same
/// treatment as release.
///
/// Takes [isDebug] rather than reading `kDebugMode` so both branches are
/// testable; `String.fromEnvironment` cannot branch on build mode in a `const`.
String resolveApiBaseUrl({required String fromEnvironment, required bool isDebug}) {
  if (fromEnvironment.isNotEmpty) return fromEnvironment;
  return isDebug ? _devFallbackApiUrl : '';
}

/// The API base URL. Empty only in a release or profile build with no `API_URL`.
final String apiBaseUrl = resolveApiBaseUrl(
  fromEnvironment: _apiUrlFromEnvironment,
  // Must stay `kDebugMode`. `!kReleaseMode` looks equivalent but is `true` in
  // profile mode, which would let profile builds silently fall back to the dev
  // tunnel. No test covers this wiring — only the pure helper is testable.
  isDebug: kDebugMode,
);

/// Terms of Service page served by the API (`ApiRoutes.Terms` on the backend).
const termsOfServicePath = '/terms';

/// Privacy Policy page served by the API (`ApiRoutes.Privacy` on the backend).
const privacyPolicyPath = '/privacy';

/// Builds the URL of a page the API serves at [path] (e.g. [privacyPolicyPath]).
///
/// Legal links must derive from the configured host rather than being
/// hardcoded: a hardcoded dev tunnel goes dead once retired (App Store
/// Guideline 5.1.1(i) requires a working privacy policy link) and, being a
/// reclaimable subdomain, would hand a third party the app's own legal pages.
/// Tolerates a trailing slash on [baseUrl] so `API_URL=https://host/` works.
Uri apiPageUri(String baseUrl, String path) {
  final trimmedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  return Uri.parse('$trimmedBase$path');
}

/// Describes why the API host is unusable, or `null` when it is fine. The
/// bootstrap fails closed on a non-null value instead of letting the app run
/// against an unintended host.
String? apiBaseUrlConfigError(String baseUrl) {
  if (baseUrl.isNotEmpty) return null;
  return 'API_URL was not provided at build time. Release and profile builds must pass '
      '--dart-define=API_URL=https://your-api-host';
}

/// True when [e] means the backend could not be reached at all — no network,
/// DNS failure, connection refused, or a timeout — as opposed to the server
/// answering with an HTTP error. Callers use this to decide whether an
/// already-authenticated user should fall back to their cached profile and
/// continue offline (issue #19) rather than being sent back to login.
bool isServerUnreachable(Object e) {
  if (e is! DioException) return false;
  switch (e.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return true;
    case DioExceptionType.unknown:
      return e.error is SocketException;
    default:
      return false;
  }
}

/// Result of a claim preview: the hex boundaries to draw, plus the server's
/// authoritative loop count (area-validated + de-duplicated) for display (#21).
class PreviewResult {
  final List<List<List<double>>> boundaries;
  final int loopCount;

  const PreviewResult({required this.boundaries, required this.loopCount});

  /// Parses the `/api/claims/preview` response. A missing `loopCount` defaults
  /// to 0 (e.g. an older server), and missing/empty boundaries to none. Pure —
  /// unit-testable without a live HTTP call.
  factory PreviewResult.fromJson(Map<String, dynamic> json) {
    final boundaries = ((json['boundaries'] as List?) ?? const [])
        .map((b) => (b as List)
            .map((p) => (p as List).map((n) => (n as num).toDouble()).toList())
            .toList())
        .toList();
    final loopCount = (json['loopCount'] as num?)?.toInt() ?? 0;
    return PreviewResult(boundaries: boundaries, loopCount: loopCount);
  }
}

/// Service class that encapsulates all HTTP communication with the backend.
///
/// Uses [Dio] with a configurable base URL (defaults to Android emulator
/// localhost). Each public method maps 1:1 to a backend API endpoint and
/// returns strongly-typed model objects.
class ApiService {
  final Dio _dio;

  /// [dio] is injectable for tests (e.g. to drive a probe failure); production
  /// callers omit it and get the standard timeout-configured client.
  ApiService({String? baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? apiBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // W3C trace context — the backend adopts this as the request trace id,
        // so mobile actions, server logs, and crash reports share one id.
        options.headers['traceparent'] = TraceContext.newTraceparent();

        // Mock walk simulator (#29): in debug builds, while the simulator is on,
        // tag the request so the backend splits its logs into MockLogs/. The flag
        // marks logging only — no server game logic branches on it.
        if (kDebugMode && MockWalkMode.active) {
          options.headers[MockWalkConstants.requestHeader] = MockWalkConstants.requestHeaderValue;
        }

        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final token = await user.getIdToken();
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  /// Returns true if the backend is reachable right now.
  ///
  /// Hits the anonymous health endpoint with a short timeout. Used to gate
  /// actions that are meaningless offline — chiefly starting a journey, since
  /// hex capture is server-validated (anti-cheat + claim authority) and a walk
  /// started with no server gives the user no preview, no claims, and no
  /// feedback (issue #35). A server that answers with an HTTP error still
  /// counts as reachable; only a true network failure returns false. See
  /// [isServerUnreachable].
  Future<bool> isServerReachable() async {
    final timeout = const Duration(
      seconds: AppConstants.serverReachabilityTimeoutSeconds,
    );
    try {
      await _dio.get(
        _healthCheckPath,
        options: Options(receiveTimeout: timeout, sendTimeout: timeout),
      );
      return true;
    } on DioException catch (e) {
      if (isServerUnreachable(e)) return false;
      // Server answered (even an error status) → it is reachable.
      return true;
    } catch (e) {
      // A non-Dio throw escapes the catch above — most plausibly the request
      // interceptor's offline `getIdToken()` refresh raising a
      // FirebaseAuthException when the cached token is expired and there is no
      // network. Treat the probe as failed-closed (unreachable) so the caller
      // shows the offline message instead of an unhandled error crashing the
      // journey-start flow. Logged so a genuine bug here isn't masked as offline.
      _log.warning('isServerReachable probe failed with a non-Dio error', e);
      return false;
    }
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

  /// Gets exploration stats for all of the user's explored neighborhoods.
  /// Returns explored % for each neighborhood (H3 res 8).
  Future<List<ExplorationNeighborhood>> getExplorationStats({
    required String userId,
  }) async {
    final response = await _dio.get('/api/territories/exploration/$userId');
    final list = response.data as List;
    return list.map((j) => ExplorationNeighborhood.fromJson(j as Map<String, dynamic>)).toList();
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
    required String walkSessionId,
  }) async {
    final response = await _dio.post('/api/claims', data: {
      'userId': userId,
      'path': path,
      // Shared with this walk's batch-step claims so the server folds them into one
      // Claim instead of adding a separate loop-claim row (#56).
      'walkSessionId': walkSessionId,
      // Local day so this loop claim progresses the player's "today" missions.
      'localDate': localGameDay(),
    });
    return response.data as Map<String, dynamic>;
  }

  /// Batch step claim — sends N queued GPS points in a single transaction.
  /// Returns the server response, or null on network failure or when
  /// [cancelToken] is cancelled.
  Future<BatchResult?> claimBatchStep({
    required String userId,
    required String localDate,
    required String walkSessionId,
    required List<QueuedStepPoint> points,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.post(
        '/api/claims/batch-step',
        data: {
          'userId': userId,
          'localDate': localDate,
          // One walk = one Claim (#56): all of a walk's batches share this id.
          'walkSessionId': walkSessionId,
          'points': points.map((p) => p.toJson()).toList(),
        },
        cancelToken: cancelToken,
      );
      final data = response.data as Map<String, dynamic>;
      return BatchResult.fromJson(data);
    } on DioException catch (e) {
      // Cancelled by the drain on sign-out (#110): not a server verdict, so it
      // must never be read as a permanent rejection that drops points. Returning
      // null takes the drain's transient branch, which leaves the queue alone.
      if (CancelToken.isCancel(e)) {
        _log.fine('Batch step claim cancelled');
        return null;
      }
      // A 4xx is a PERMANENT rejection (bad coordinates, anti-cheat speed
      // violation, etc.) — retrying the identical batch will always fail, so
      // signal the caller to drop these points and surface the reason rather
      // than backing off forever. Everything else (5xx / timeout / offline) is
      // transient and returns null so the drainer retries with backoff.
      final status = e.response?.statusCode;
      if (status != null && status >= 400 && status < 500) {
        throw BatchRejectedException(extractApiError(e) ?? 'Batch rejected by server');
      }
      _log.warning('Batch step claim transient failure: ${e.message}');
      return null;
    } catch (e) {
      _log.warning('Batch step claim failed', e);
      return null;
    }
  }

  /// The server's explanation for a refused request — only for 4xx responses, where the body is
  /// a message written for the player. A 5xx or proxy error page is not, and must be logged
  /// rather than shown (#193 review).
  static String? clientErrorReason(Object error) {
    final status = error is DioException ? error.response?.statusCode : null;
    if (status == null || status < 400 || status >= 500) return null;
    return extractApiError(error);
  }

  /// Extracts the server's message from a failed response — a `{ "error": "..." }` body, a
  /// `{ "code": "...", "message": "..." }` body (e.g. 409 `name_locked`, DR-002b §4.2) or a plain
  /// string — or null if none is present (MEDIUM-5: surface real API errors to the user
  /// instead of a generic failure).
  static String? extractApiError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        for (final key in const ['error', 'message']) {
          final value = data[key];
          if (value is String && value.isNotEmpty) return value;
        }
      }
      if (data is String && data.isNotEmpty) return data;
    }
    return null;
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

  /// Fetches the FULL game state in one call: profile, XP, missions,
  /// achievements, exploration, rank. Single network round-trip.
  Future<Map<String, dynamic>?> getGameState(String userId) async {
    try {
      // Send the device local day so the missions in the game-state payload resolve to the
      // player's "today" (consistent with getDailyMissions and the claim paths).
      final response = await _dio.get(
        '/api/users/$userId/game-state',
        queryParameters: {'localDate': localGameDay()},
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      _log.warning('getGameState failed', e);
      return null;
    }
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

  /// Ids of the players the signed-in user has blocked (DR-002b, #190).
  Future<Set<String>> getBlockedUserIds() async {
    final response = await _dio.get('/api/users/me/blocks');
    final ids = (response.data as Map<String, dynamic>)['blockedUserIds'] as List;
    return ids.cast<String>().toSet();
  }

  /// Blocks [userId]: their name is masked for the caller. Idempotent on the server.
  Future<void> blockUser(String userId) async {
    await _dio.put('/api/users/$userId/block');
  }

  /// Unblocks [userId]. Idempotent on the server.
  Future<void> unblockUser(String userId) async {
    await _dio.delete('/api/users/$userId/block');
  }

  /// Reports [userId]'s display name. [reason] is the wire value
  /// ("offensive" | "impersonation" | "other").
  Future<void> reportName(String userId, String reason) async {
    await _dio.post('/api/users/$userId/name-reports', data: {'reason': reason});
  }

  /// Permanently deletes the user account and all associated data.
  Future<void> deleteAccount(String userId) async {
    await _dio.delete('/api/users/$userId');
  }

  /// Updates user profile fields (display name, avatar, color).
  Future<void> updateUser({
    required String userId,
    String? displayName,
    int? avatarId,
    String? color,
  }) async {
    final data = <String, dynamic>{};
    if (displayName != null) data['displayName'] = displayName;
    if (avatarId != null) data['avatarId'] = avatarId;
    if (color != null) data['color'] = color;
    if (data.isEmpty) return;
    await _dio.patch('/api/users/$userId', data: data);
  }

  /// Registers an FCM device token for push notifications.
  Future<void> registerDeviceToken({required String userId, required String token}) async {
    await _dio.post('/api/users/$userId/device-token', data: {
      'token': token,
      'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    });
  }

  /// Sets the user's home location for decay calculations.
  /// Called during onboarding after registration.
  Future<Map<String, dynamic>> setHome({
    required String userId,
    required double lat,
    required double lng,
  }) async {
    final response = await _dio.post('/api/users/$userId/home', data: {
      'lat': lat,
      'lng': lng,
    });
    return response.data as Map<String, dynamic>;
  }

  /// Fetches paginated walk history (claims) for a user.
  Future<List<Map<String, dynamic>>> getWalkHistory({
    required String userId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get(
      '/api/users/$userId/claims',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  /// Preview which hexes a path would capture — no DB writes.
  /// Called during a walk when a loop is detected to show live hex fills.
  ///
  /// Returns the hex boundaries plus the server's authoritative loop count
  /// (area-validated + de-duplicated), which the app shows instead of its own
  /// raw closure count (issue #21).
  Future<PreviewResult> previewClaim({
    required List<List<double>> path,
  }) async {
    final response = await _dio.post('/api/claims/preview', data: {
      'path': path,
    });
    return PreviewResult.fromJson(response.data as Map<String, dynamic>);
  }

  // --- Missions & XP ---

  /// Get today's daily missions for the user (generates if needed).
  Future<List<DailyMission>> getDailyMissions(String userId) async {
    // Send the device local day so missions resolve to the player's "today", not server UTC.
    final response = await _dio.get(
      '/api/missions/$userId',
      queryParameters: {'localDate': localGameDay()},
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => DailyMission.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get user's XP and level info.
  Future<XpInfo> getXpInfo(String userId) async {
    final response = await _dio.get('/api/missions/xp/$userId');
    return XpInfo.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get all achievements with user's progress and unlock status.
  Future<List<Achievement>> getAchievements(String userId) async {
    final response = await _dio.get('/api/achievements/$userId');
    final list = response.data as List<dynamic>;
    return list
        .map((e) => Achievement.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Riverpod provider exposing a singleton [ApiService] instance.
///
/// Inject via `ref.read(apiServiceProvider)` to access the API client
/// from any widget or controller.
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

/// Thrown when the server permanently rejects a batch (HTTP 4xx) — e.g. an
/// anti-cheat speed violation. The contained [message] is the server-supplied
/// reason, suitable for display. The drainer drops the offending points rather
/// than retrying a batch that can never succeed.
class BatchRejectedException implements Exception {
  final String message;
  BatchRejectedException(this.message);

  @override
  String toString() => 'BatchRejectedException: $message';
}
