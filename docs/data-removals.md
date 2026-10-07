# Data-removal register

Every file that deletes, overwrites, hands over or expires user data, and what that means for the requirements.
Scenario DATA-1 (`docs/scenarios.md`). "PR rules" fails a file that has such code and isn't listed here, and a row
whose file no longer exists.

**How it works**
- The script looks for these patterns. Server (`api/`, not `Migrations/`): `ExecuteDelete`, `ExecuteUpdate`,
  `ExecuteSql` (any raw SQL, which covers `UPDATE`), `DELETE FROM`, `.Remove(`, `.RemoveRange(`, `TRUNCATE`,
  `DROP TABLE`, `DROP COLUMN`, `.OwnerId = `. Phone (`mobile/lib/shared/`): `writeAsString(`, `.rename(`, `.delete(`,
  `deleteSync(`, `removeWhere(`, `.removeAt(`, `.removeRange(`, `.clear()`.
- Not seen by the script: `SaveChanges` that replaces a tracked entity, `.remove(` on a map or set, and phone code
  outside `mobile/lib/shared/`. Review those by eye, and list the file by hand if it matters.
- **Verdict:** `keeps #N` (the code serves requirement N), `keeps none — <reason>` (no requirement is involved, say
  why), or `breaks #N` (it works against requirement N). A `breaks` row needs an owner, an FR or a task (`FR6`, `#201`).
  A fix that makes a `breaks` row right changes the verdict in the same PR.
- **Known limit:** the script sees only direct statements. A file that makes another file delete (for example by
  calling a queue's drop method) is invisible to it, so list that caller by hand, as the last two phone rows do.
  The script does not check that the `#N` in a verdict exists. A file appears in one row only.
- Add a row in the same PR that adds such code. Keep it to one line per file.

| File | What it removes or hands over | Verdict | Owner |
|---|---|---|---|
| `api/MyLoop.Api/Data/DbInitializer.cs` | When an owned hex has no explored row for its owner, startup deletes every player's explored hexes and rebuilds them from owned land (line 103, audit A2; also breaks #43); also removes duplicate daily-mission rows | breaks #5 | FR7 |
| `api/MyLoop.Api/Services/TerritoryService.cs` | A claim hands a hex that another player owns to the claimant (`cell.OwnerId = userId`, line 1139) | breaks #43 | FR6 |
| `api/MyLoop.Api/Services/DecayCleanupService.cs` | Every hour, deletes land not refreshed within `DecayDays` (line 215) | breaks #43 | FR6 |
| `api/MyLoop.Api/Services/UserService.cs` | Account deletion purges the user's rows without the per-user lock, and four tables have no cascade (audit A4) | breaks #40 | FR12 |
| `api/MyLoop.Api/Services/LeaderboardService.cs` | Deletes today's and old leaderboard snapshot rows | keeps none — a derived snapshot, not user-owned data | - |
| `api/MyLoop.Api/Services/Moderation/BlockService.cs` | Unblock deletes the caller's own block row | keeps none — the caller's own request | - |
| `api/MyLoop.Api/Services/PushNotificationService.cs` | Deletes device tokens the push service reports as dead | keeps none — dead tokens only | - |
| `mobile/lib/shared/services/api_service.dart` | Calls the server to unblock a player and to delete the account | keeps #40 | - |
| `mobile/lib/shared/services/auth_service.dart` | Deletes the Firebase user when the account is deleted | keeps #40 | - |
| `mobile/lib/shared/services/step_claim_queue.dart` | Removes queued step claims after a send and clears the queue | breaks #9 | FR3 |
| `mobile/lib/shared/services/batch_drain_service.dart` | Drops queued GPS points when the server answers 4xx or rejects one hop (audit A7); no direct statement, listed by hand | breaks #9 | FR3 |
| `mobile/lib/features/journey/journey_controller.dart` | Empties the step-claim queue (lines 490, 523); no pattern matches this folder, listed by hand | breaks #9 | FR3 |
| `mobile/lib/shared/services/profile_cache.dart` | Deletes this phone's saved profile on sign-out | keeps none — clears this phone's copy; the server copy stays | - |
| `mobile/lib/shared/services/game_state_cache.dart` | Deletes this phone's saved game state on sign-out | keeps none — clears this phone's copy; the server copy stays | - |
| `mobile/lib/shared/services/territory_cache.dart` | Deletes this phone's saved land on sign-out | keeps none — clears this phone's copy; the server copy stays | - |
| `mobile/lib/shared/services/block_list_cache.dart` | Deletes this phone's saved block list on sign-out | keeps none — clears this phone's copy; the server copy stays | - |
| `mobile/lib/shared/services/notification_cache.dart` | Deletes this phone's saved inbox on sign-out | keeps none — clears this phone's copy; the server copy stays | - |
| `api/MyLoop.Api/Services/HexCountReconciliationService.cs` | Rewrites each user's `HexCount` from their land | keeps none — a derived count, the land itself is untouched | - |
| `api/MyLoop.Api/Services/Moderation/NameHiding.cs` | Replaces a reported display name with a placeholder, and restores it | keeps none — a reversible hide of a name the owner chose | - |
| `api/MyLoop.Api/Services/Moderation/ModerationService.cs` | Overwrites name locks, strikes and case status | keeps none — moderation records, not walk or land data | - |
| `api/MyLoop.Api/Services/Moderation/NameReportService.cs` | Writes and updates name reports | keeps none — moderation records, not walk or land data | - |
| `api/MyLoop.Api/Services/Moderation/ModerationLocks.cs` | Takes database advisory locks only | keeps none — locks, no stored data | - |
| `mobile/lib/shared/rules/rules_store.dart` | Replaces the saved copy of the game rules | keeps none — a copy of server rules, rebuilt from the server | - |
| `mobile/lib/shared/services/mock/mock_route_store.dart` | Replaces the debug mock-route file | keeps none — debug builds only | - |
| `mobile/lib/shared/services/territory_realtime_service.dart` | Clears the in-memory list of subscribed map regions | keeps none — in memory only | - |
| `mobile/lib/shared/services/app_logger.dart` | Clears the in-memory log buffer | keeps none — in memory only | - |
