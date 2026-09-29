# MyLoop 0.1 — independent audit (master 26121e0, 2026-09-29)

5 agents audited the code independently. Each read only `requirements.md` for the 0.1 goal, and none saw the tasks, PRs, design docs or FR1 record.
"Verified" = the agent ran a probe in a throwaway copy. "Code" = the agent found it by reading the code.
Duplicate findings across agents are merged.

## A. Fix now — live harm today

| # | Finding | Where | Effect on user | Confidence |
|---|---|---|---|---|
| A1 | The live map feed (SignalR hub) accepts connections without sign-in and broadcasts every capture with the owner's id and name. Territory, user and leaderboard endpoints show other players' data. | `Hubs/TerritoryHub.cs:13,47-62`, `TerritoryNotifier.cs:31-50`, `TerritoryController.cs:41-82`, `UsersController` | A stranger can follow players' walks live. Breaks the single-player rule (#1). No FR owns fixing it. | code |
| A2 | Server startup can delete all players' exploration. It rebuilds "explored" from owned land, and the seeded bot land triggers that rebuild. | `Data/DbInitializer.cs:91-120` | Explored hexes are lost (#5, #28). | verified |
| A3 | Bot users and bot land are seeded in every environment, Production included. | `DbInitializer.cs:28`, `SeedUsers.cs` | Fake rivals appear on a single-player map, and it is re-seeded after a reset. | code |
| A4 | Deleting an account doesn't take the per-user lock. 4 tables have no cascade. | `UserService.cs:92` | Rows outlive "delete account" (#40). | verified |
| A5 | The uid→user-id cache (5 min) is not cleared on delete. | `CurrentUser.cs:51-58` | Signing up again right after deleting gives 403s, or claims saved under the deleted id. | verified |
| A6 | The phone's sign-in step throws when the token expires offline, and Dio never finishes the request. | `api_service.dart:157-179` | Start walk hangs. Point sending stops for the rest of the walk. | verified |
| A7 | Any 4xx (401, 429, daily limit) or one bad GPS hop in a 5-point batch deletes those points from the phone. | `api_service.dart:269-272,364`, `batch_drain_service.dart:177-188`, `PathValidationService.cs:141-170` | Honest walks lose points, and the user is told "anti-cheat". | verified |
| A8 | The end-of-walk loop claim is sent only if the live preview saw a loop. The preview sees the last 500 points, and a failed preview is never retried. The claim is sent once and never saved or retried. | `journey_controller.dart:531-580`, `journey_screen.dart:57-127`, `app_constants.dart:65` | A real loop is silently never captured (#6, #35). | code |
| A9 | Point timestamps are when the app saved the point, not when GPS fixed it. | `journey_controller.dart:367-370` | Batched fixes look like impossible speed, the batch is rejected, and then deleted (A7). | verified |

## B. FR1 (marked done) — bugs in what it delivered

Per the "keeping records true" rule, these need an FR1 fix PR, and the FR1 record must be updated.

| # | Finding | Where | Confidence |
|---|---|---|---|
| B1 | `Infinity` passes rules validation. The server starts, and then every request that needs the rules returns 500. A max speed of `Infinity` turns the speed check off. | `GameRulesValidator.cs:15-18`, `RuleSettings.cs:31` | verified |
| B2 | The first GPS fix of a walk skips the accuracy threshold. It is taken before the rules are pinned and is never sent to the server. | `journey_controller.dart:214,227` | verified |
| B3 | `Loop:SkipNeighbors` has no effect at any value up to `MinPoints` (20), and its comment is wrong. | `HexGridService.cs:236-238,361-365`, `loop_detector.dart:30-32`, `GameRules.cs:34` | code (arithmetic) |
| B4 | Walk start waits on a refresh that is already running (which may be stuck on a dead socket) instead of making a new 3 s request. | `game_rules_provider.dart:66-69` | code |
| B5 | Rule values have no upper limits, so a typo like 500 instead of 50 passes startup. | `GameRulesValidator.cs` | verified |
| B6 | The walk-start timing tests use real time and check ≤5 s instead of 3 s. | `rules_consistency_test.dart:373-399` | code |
| B7 | The rules contract test doesn't go through the real HTTP pipeline (auth, casing, ETag header). This is partly documented as accepted. | `ContractTests.cs:13` | code |
| B8 | Stale comments: "resuming after a pause" and "(#37)". | `GameRules.cs:28,58` | code |

## C. Capture and anti-cheat — the old code gives wrong results (FR4–FR8 will replace it)

| # | Finding | Confidence |
|---|---|---|
| C1 | A figure-8 captures only one half, because the whole-path ring crosses itself and its area cancels out (`HexGridService.cs:331-389`). | verified |
| C2 | A second loop that ends on an earlier loop's edge captures nothing (`used` points can't close again). | verified |
| C3 | The loop claim trusts any path the phone sends. It isn't checked against the points already sent, and it can be replayed. A made-up loop and a loop driven at 50 km/h both passed. | verified |
| C4 | Speed has no check across batches. A 3 km jump passes inside a 200-point batch. Equal or backwards timestamps count as 5 s apart. | verified |
| C5 | Every hex on the path is captured, even without a loop. The spec says trail hexes don't capture. | code |
| C6 | A 20 km loop took 2.3 s and 120 MB, so a very large loop can take down the API. One loop over 5 km² rejects the whole claim. | verified |
| C7 | Walking up one side of a street and back the other counts as a loop. | verified |
| C8 | Exploration covers only the hex each point is in, not the hexes between points, and loop-filled hexes are marked explored. | code |
| C9 | Loops close by being near an earlier point, not by crossing it, so sparse crossings are missed. | code |
| C10 | Phone and server use different earth radii (6,378,137 m vs 6,371,000 m). | code |
| C11 | Two tests don't guard what they claim: the teleport test uses a 2-point batch, and the out-and-back test has zero width. | code |

## D. Walk tracking and device (FR2–FR4 not built; the old code loses data)

- **D1:** points left at Stop, or after an app kill, are sent only when the next walk starts. `drainBeforeCapture` is dead code. Sign-out deletes unsent points.
- **D2:** revoking location or turning GPS off mid-walk leaves the walk stuck on "Recording" with no message, because the stream has no `onError`.
- **D3:** a failed start (for example, disk full) leaves the walk frozen in the `tracking` state.
- **D4:** saving a point can fail with nobody noticing. A half-written last line then corrupts the next one.
- **D5:** a new walk and the old drain both write to the same saved-points file, so the old drain's stale copy wipes the new walk's points on disk.
- **D6:** server distance misses the hop between batches (about 20% short) and is counted twice on a retry. XP is also counted twice.
- **D7:** walk history dates older than 7 days show UTC, not local time.
- **D8:** not built yet:
  - pause and auto-end;
  - offline start (it is blocked today);
  - precise vs approximate location;
  - the weak-GPS message;
  - notification permission and the safety alarm;
  - gap handling.
- **D9:** the tests for the saved-points file, the drain and the location settings don't run in CI.

## E. Accounts, data, product

- **E1:** "Create account without login" leads to a dead end and leaves an account that can never be signed into or deleted.
- **E2:** exploration counts drop when land decays (an inner join with owned land).
- **E3:** if deleting the Firebase user fails, it is left behind, and the Apple token is never revoked. App Store 5.1.1(v) risk.
- **E4:** home location is wider than `HomeLocation.cs`: the Home* columns, City/Country, and exact coordinates written to logs. Removing the entity properties alone leaves the columns in the database.
- **E5:** stealing, decay (removes land every hour), leaderboard, missions and public profiles all still run.
- **E6:** no global 401 handling. The "SKIP (DEV MODE)" button shows in profile builds.
- **E7:** H3 ids are sent as a number over REST and as a string over SignalR. Only the rules endpoint has a contract test.
- **E8:** the EF migrations are dead and stale (the app uses `EnsureCreated` plus hand-written SQL). A failed schema patch only logs a warning.
- **E9:** `google-services.json` and `GoogleService-Info.plist` are committed, but `.gitignore` and CLAUDE.md say they are not.
- **E10:** CI's `flutter analyze` never fails on warnings; only `verify.sh` enforces the baseline.
- **E11:** fat controllers (`UsersController`, `MissionsController`) query the database directly.
- **E12:** there is no `PrivacyInfo.xcprivacy`.

## Checked and fine

- A hex counts if its centre is inside the loop, at H3 resolution 11.
- Standing still and then walking a loop captures correctly.
- Anti-cheat numbers never reach the phone, and neither do rejection details.
- The 0.1 tests pass: 56 .NET and 95 Flutter. Analyze is at its baseline of 20.
