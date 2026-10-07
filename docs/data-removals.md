# Data-removal register

Every file that deletes, overwrites, hands over or expires user data, and what that means for the requirements.
Scenario DATA-1 (`docs/scenarios.md`). "PR rules" fails a file that has such code and isn't listed here, and a row
whose file no longer exists.

**How it works**
- The script looks for these patterns. Server (`api/`, not `Migrations/`): `ExecuteDelete`, `DELETE FROM`, `.Remove(`,
  `.RemoveRange(`, `TRUNCATE`, `DROP TABLE`, `DROP COLUMN`, `.OwnerId = `. Phone (`mobile/lib/shared/services/` and
  `mobile/lib/shared/state/`): `.delete(`, `deleteSync(`, `removeWhere(`, `.removeAt(`, `.removeRange(`, `.clear()`.
- **Verdict:** `keeps #N` (the code serves requirement N), `keeps none — <reason>` (no requirement is involved, say
  why), or `breaks #N` (it works against requirement N). A `breaks` row needs an owner, an FR or a task (`FR6`, `#201`).
  A fix that makes a `breaks` row right changes the verdict in the same PR.
- **Known limit:** the script sees only direct statements. A file that makes another file delete (for example by
  calling a queue's drop method) is invisible to it, so list that caller by hand, as the last row does.
- Add a row in the same PR that adds such code. Keep it to one line per file.

| File | What it removes or hands over | Verdict | Owner |
|---|---|---|---|
| `api/MyLoop.Api/Data/DbInitializer.cs` | Startup deletes every player's explored hexes and rebuilds them from owned land (line 103, audit A2); also removes duplicate daily-mission rows | breaks #5 | #201 |
| `api/MyLoop.Api/Services/TerritoryService.cs` | A claim hands a hex that another player owns to the claimant (`cell.OwnerId = userId`, line 1139) | breaks #43 | FR6 |
| `api/MyLoop.Api/Services/DecayCleanupService.cs` | Every hour, deletes land not refreshed within `DecayDays` (line 215) | breaks #43 | FR15 |
| `api/MyLoop.Api/Services/UserService.cs` | Account deletion purges the user's rows without the per-user lock, and four tables have no cascade (audit A4) | breaks #40 | FR12 |
| `api/MyLoop.Api/Services/LeaderboardService.cs` | Deletes today's and old leaderboard snapshot rows | keeps none — a derived snapshot, not user-owned data | - |
| `api/MyLoop.Api/Services/Moderation/BlockService.cs` | Unblock deletes the caller's own block row | keeps none — the caller's own request | - |
| `api/MyLoop.Api/Services/PushNotificationService.cs` | Deletes device tokens the push service reports as dead | keeps none — dead tokens only | - |
| `mobile/lib/shared/services/api_service.dart` | Calls the server to unblock a player and to delete the account | keeps #40 | - |
| `mobile/lib/shared/services/auth_service.dart` | Deletes the Firebase user when the account is deleted | keeps #40 | - |
| `mobile/lib/shared/services/step_claim_queue.dart` | Removes queued step claims after a send and clears the queue | breaks #9 | FR3 |
| `mobile/lib/shared/services/batch_drain_service.dart` | Drops queued GPS points when the server answers 4xx or rejects one hop (audit A7); no direct statement, listed by hand | breaks #9 | FR3 |
| `mobile/lib/shared/services/profile_cache.dart` | Deletes this phone's saved profile on sign-out | keeps none — clears this phone's copy; the server copy stays | - |
| `mobile/lib/shared/services/game_state_cache.dart` | Deletes this phone's saved game state on sign-out | keeps none — clears this phone's copy; the server copy stays | - |
| `mobile/lib/shared/services/territory_cache.dart` | Deletes this phone's saved land on sign-out | keeps none — clears this phone's copy; the server copy stays | - |
| `mobile/lib/shared/services/block_list_cache.dart` | Deletes this phone's saved block list on sign-out | keeps none — clears this phone's copy; the server copy stays | - |
| `mobile/lib/shared/services/notification_cache.dart` | Deletes this phone's saved inbox on sign-out | keeps none — clears this phone's copy; the server copy stays | - |
| `mobile/lib/shared/services/territory_realtime_service.dart` | Clears the in-memory list of subscribed map regions | keeps none — in memory only | - |
| `mobile/lib/shared/services/app_logger.dart` | Clears the in-memory log buffer | keeps none — in memory only | - |
