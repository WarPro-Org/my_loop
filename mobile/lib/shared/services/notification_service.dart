/// In-app notification store.
///
/// Captures territory theft events from SignalR and push messages
/// so users can see a history of what happened to their territory.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A single in-app notification entry.
class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
  });
}

/// Riverpod notifier that manages the in-app notification list.
class NotificationNotifier extends Notifier<List<AppNotification>> {
  @override
  List<AppNotification> build() => [];

  void addTheftAlert({
    required String thiefName,
    required String thiefColor,
    required int hexCount,
  }) {
    final n = AppNotification(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: 'Territory Under Attack! ⚔️',
      body: '$thiefName captured $hexCount of your hex${hexCount == 1 ? '' : 'es'}!',
      timestamp: DateTime.now(),
    );
    state = [n, ...state.take(49)]; // Keep last 50
  }

  void markAllRead() {
    state = state.map((n) => AppNotification(
      id: n.id,
      title: n.title,
      body: n.body,
      timestamp: n.timestamp,
      isRead: true,
    )).toList();
  }

  void clear() => state = [];

  int get unreadCount => state.where((n) => !n.isRead).length;
}

final notificationProvider =
    NotifierProvider<NotificationNotifier, List<AppNotification>>(
  NotificationNotifier.new,
);

/// Convenience selector: number of unread notifications.
final unreadCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationProvider);
  return notifications.where((n) => !n.isRead).length;
});
