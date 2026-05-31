/// Push notification service — requests permission, gets FCM token,
/// registers with backend, and handles incoming notifications.
library;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/services/api_service.dart';

class PushNotificationService {
  final ApiService _api;
  String? _currentToken;

  PushNotificationService({required ApiService api}) : _api = api;

  /// Initialize push notifications — request permission and register token.
  /// Call this after the user is logged in and userId is available.
  Future<void> initialize(String userId) async {
    final messaging = FirebaseMessaging.instance;

    // Request permission (iOS shows system dialog, Android auto-grants)
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    // Get FCM token
    final token = await messaging.getToken();
    if (token != null) {
      _currentToken = token;
      await _registerToken(userId, token);
    }

    // Listen for token refresh
    messaging.onTokenRefresh.listen((newToken) {
      _currentToken = newToken;
      _registerToken(userId, newToken);
    });
  }

  Future<void> _registerToken(String userId, String token) async {
    try {
      await _api.registerDeviceToken(userId: userId, token: token);
    } catch (_) {
      // Non-critical — will retry on next app open
    }
  }

  String? get currentToken => _currentToken;
}

final pushNotificationProvider = Provider<PushNotificationService>((ref) {
  final api = ref.read(apiServiceProvider);
  return PushNotificationService(api: api);
});
