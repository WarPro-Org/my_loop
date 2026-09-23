import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/services/notification_cache.dart';
import 'package:myloop/shared/services/notification_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir, {this.callDelays = const []});
  final String dir;

  /// Delay applied to the n-th call (index n); calls past the end are instant.
  /// Lets a test make one write's await point slower than a later write's, which
  /// is how two unserialized writes land on disk out of order.
  final List<Duration> callDelays;
  int _calls = 0;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final call = _calls++;
    if (call < callDelays.length) await Future<void>.delayed(callDelays[call]);
    return dir;
  }
}

AppNotification _alert(String id, {bool isRead = false}) => AppNotification(
      id: id,
      title: 'Territory Under Attack! ⚔️',
      body: 'Robin captured 3 of your hexes!',
      timestamp: DateTime.utc(2026, 6, 15, 10),
      isRead: isRead,
    );

/// Sets the signed-in user id the notification notifier binds its cache to.
ProviderContainer _containerForUser(String userId) {
  final c = ProviderContainer();
  c.read(userProfileProvider.notifier).setFromApi(
        userId: userId,
        avatarId: 1,
        color: '#FF0000',
        displayName: 'Robin',
        hexCount: 0,
        streak: 0,
        distanceKm: 0,
      );
  return c;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('notification_cache_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('NotificationCache', () {
    test('encode/decode is a pure round-trip', () {
      final raw = NotificationCache.encode('u1', [_alert('a'), _alert('b', isRead: true)]);
      final decoded = NotificationCache.decode(raw)!;
      expect(decoded.userId, 'u1');
      expect(decoded.notifications.map((n) => n.id), ['a', 'b']);
      expect(decoded.notifications[1].isRead, isTrue);
    });

    test('save then load restores the inbox (disk durability)', () async {
      await NotificationCache.save('u1', [_alert('a'), _alert('b')]);
      final loaded = await NotificationCache.load('u1');
      expect(loaded!.map((n) => n.id), ['a', 'b']);
    });

    test('cross-user guard: a different user cannot load the cache', () async {
      await NotificationCache.save('u1', [_alert('a')]);
      expect(await NotificationCache.load('u2'), isNull);
    });

    test('clear removes the cache', () async {
      await NotificationCache.save('u1', [_alert('a')]);
      await NotificationCache.clear();
      expect(await NotificationCache.load('u1'), isNull);
    });
  });

  group('NotificationNotifier persistence', () {
    // Acceptance (#30): alert added → app "restart" (fresh container reads only disk) →
    // alert persists and is still unread until the screen marks it read. Proven to fail
    // without the fix: the pre-#30 in-memory notifier restored nothing on a new container.
    test('an added alert survives an app restart and stays unread', () async {
      final c1 = _containerForUser('u1');
      c1.read(notificationProvider.notifier).addTheftAlert(
            thiefName: 'Robin',
            thiefColor: '#FF0000',
            hexCount: 3,
          );
      await c1.read(notificationProvider.notifier).pendingWrite;
      c1.dispose();

      // Fresh container = app restart. build() hydrates from disk.
      final c2 = _containerForUser('u1');
      c2.read(notificationProvider); // triggers build() → _hydrate()
      await c2.read(notificationProvider.notifier).hydration;

      final restored = c2.read(notificationProvider);
      expect(restored.length, 1);
      expect(restored.first.body, contains('captured 3'));
      expect(c2.read(notificationProvider.notifier).unreadCount, 1,
          reason: 'a restored alert is unread until the screen marks it read');
      c2.dispose();
    });

    // Failed intermittently in CI (same commit passed and failed 33s apart) because it
    // slept 20ms instead of awaiting the write: hydration then read an unread inbox off
    // disk, meaning markAllRead's write had not landed. Awaiting the future is load-
    // independent, so the outcome no longer depends on how busy the machine is.
    test('markAllRead persists so unread stays 0 across a restart', () async {
      final c1 = _containerForUser('u1');
      final n1 = c1.read(notificationProvider.notifier);
      n1.addTheftAlert(thiefName: 'Robin', thiefColor: '#FF0000', hexCount: 1);
      n1.markAllRead();
      await n1.pendingWrite;
      c1.dispose();

      final c2 = _containerForUser('u1');
      c2.read(notificationProvider);
      await c2.read(notificationProvider.notifier).hydration;
      expect(c2.read(notificationProvider.notifier).unreadCount, 0);
      c2.dispose();
    });

    // Regression test for the out-of-order write. The first path lookup inside
    // NotificationCache.save is made slower than the second, so without the write
    // chain addTheftAlert's unread snapshot lands AFTER markAllRead's write and the
    // badge comes back after a restart. Proven to fail against master's
    // notification_service.dart (Expected: [true] Actual: [false]) and to pass with
    // the chain.
    test('regression: a slow earlier write cannot overwrite markAllRead on disk',
        () async {
      final c1 = _containerForUser('u1');
      final n1 = c1.read(notificationProvider.notifier);
      await n1.hydration;
      PathProviderPlatform.instance = _FakePathProvider(
        tmp.path,
        callDelays: const [Duration(milliseconds: 50)],
      );

      n1.addTheftAlert(thiefName: 'A', thiefColor: '#FF0000', hexCount: 1);
      n1.markAllRead();
      await n1.pendingWrite;
      c1.dispose();

      final onDisk = await NotificationCache.load('u1');
      expect(onDisk!.map((n) => n.isRead), [true],
          reason: 'the stale unread snapshot must not land last');
    });

    // flutter-disk-concurrency-test: disk must equal final memory after interleaved
    // unawaited mutations. On its own this does not reproduce the ordering hazard
    // (fast writes happen to land in order); the slow-first-write regression test
    // above does. This one pins the convergence property.
    test('interleaved unawaited mutations converge: disk == final memory', () async {
      final c1 = _containerForUser('u1');
      final n1 = c1.read(notificationProvider.notifier);

      n1.addTheftAlert(thiefName: 'A', thiefColor: '#FF0000', hexCount: 1);
      n1.addTheftAlert(thiefName: 'B', thiefColor: '#00FF00', hexCount: 2);
      n1.markAllRead();
      n1.addTheftAlert(thiefName: 'C', thiefColor: '#0000FF', hexCount: 3);

      final inMemory = c1.read(notificationProvider);
      await n1.pendingWrite;
      c1.dispose();

      final c2 = _containerForUser('u1');
      c2.read(notificationProvider);
      await c2.read(notificationProvider.notifier).hydration;
      final onDisk = c2.read(notificationProvider);

      expect(onDisk.map((n) => n.body), inMemory.map((n) => n.body),
          reason: 'disk holds the final ordering, not a stale snapshot');
      expect(onDisk.map((n) => n.isRead), inMemory.map((n) => n.isRead),
          reason: 'only the alert added after markAllRead stays unread');
      expect(c2.read(notificationProvider.notifier).unreadCount, 1);
      c2.dispose();
    });

    test('a second user does not inherit the first user\'s notifications', () async {
      final c1 = _containerForUser('u1');
      c1.read(notificationProvider.notifier).addTheftAlert(
            thiefName: 'Robin', thiefColor: '#FF0000', hexCount: 2);
      await c1.read(notificationProvider.notifier).pendingWrite;
      c1.dispose();

      final c2 = _containerForUser('u2');
      c2.read(notificationProvider);
      await c2.read(notificationProvider.notifier).hydration;
      expect(c2.read(notificationProvider), isEmpty);
      c2.dispose();
    });
  });
}
