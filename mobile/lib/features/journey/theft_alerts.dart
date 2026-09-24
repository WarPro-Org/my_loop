/// Turns realtime hex changes into in-app theft alerts for the signed-in player.
library;

import 'package:myloop/features/moderation/blocked_users.dart';
import 'package:myloop/shared/services/notification_service.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

/// Records one theft alert per thief for the hexes in [events] that were taken from [userId].
///
/// Grouped by thief id, not name: names are not unique (DR-002c), so two same-named thieves must
/// not merge into one alert. The alert text is persisted to the inbox, so a blocked thief's name
/// must be masked before it is written: this waits for the block list's first load
/// ([BlockedUsersNotifier.blockedIdsFor]) instead of reading the provider's state, which is still
/// empty right after sign-in (#195 review). Nothing is recorded if the account changed meanwhile.
Future<void> recordTheftAlerts({
  required String userId,
  required List<HexChangeEvent> events,
  required BlockedUsersNotifier blockedUsers,
  required NotificationNotifier notifications,
}) async {
  final stolenByThief = <String, List<HexChangeEvent>>{};
  for (final e in events) {
    if (e.previousOwnerId == userId && e.newOwnerId != userId) {
      stolenByThief.putIfAbsent(e.newOwnerId, () => []).add(e);
    }
  }
  if (stolenByThief.isEmpty) return;

  final blocked = await blockedUsers.blockedIdsFor(userId);
  if (blocked == null) return;
  for (final MapEntry(key: thiefId, value: stolen) in stolenByThief.entries) {
    notifications.addTheftAlert(
      thiefName: actorNameFor(blocked, thiefId, stolen.first.newOwnerDisplayName),
      thiefColor: stolen.first.newOwnerColor,
      hexCount: stolen.length,
    );
  }
}
