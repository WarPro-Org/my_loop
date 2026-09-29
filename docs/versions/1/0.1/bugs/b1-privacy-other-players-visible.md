# Bug B1 — Other players' land, names and activity are visible (breaks single-player 0.1)

**Status:** approved by the owner 2026-09-29 (Bug Gate 1); task #223. Found by the 2026-09-29 blind audit (A1).
**Scenarios:** PRIV-1, PRIV-2, PRIV-6, LEG-1 (`docs/scenarios.md`).

## Symptom

**Expected:** requirement #1 says that in 0.1, every user's land and exploration is visible only to that user.

**Observed:** any signed-in user can see other players, and the live map feed needs no sign-in at all.

| Where | What leaks | Who can see it |
|---|---|---|
| Live map feed `/hubs/territory`, `JoinRegion` (`Hubs/TerritoryHub.cs:13-62`) | Every capture in a region, live: hex, centre, owner id, colour and **display name** (`Services/TerritoryNotifier.cs:31-50`) | **Anyone, with no sign-in** (the hub class at `TerritoryHub.cs:14` has no `[Authorize]`) |
| `GET /api/territories?minLat…` (`Controllers/TerritoryController.cs:41-58`) | Every player's hexes in any map area | Any signed-in user |
| `GET /api/territories/user/{id}` (`TerritoryController.cs:77-82`) | All hexes of any player, often around their home | Any signed-in user |
| `GET /api/users/{id}`, `GET /api/users/{id}/profile` (`Controllers/UsersController.cs:133-139, 202-208`) | Any player's name, stats and rank | Any signed-in user |
| `GET /api/leaderboard` (`Controllers/LeaderboardController.cs:27-37`) | Top 20 players by city, country or world | Any signed-in user |
| Push "X captured N of your hexes!" (`Services/PushNotificationService.cs:28-44`) | Another player's name | The player who lost the hexes |

The first row is the worst. A stranger can follow where players walk, in real time, without an account.

## Reproduction steps

1. Open a SignalR connection to `/hubs/territory` with no token.
2. Call `JoinRegion("<any H3 res-3 cell id near a city>")`.
3. Have any player capture a hex in that region. The stranger's connection receives `HexOwnershipChanged` with that player's id, name and hex centre.
4. Signed in as user A, call `GET /api/territories/user/<user B's id>`. It returns B's hexes.
5. Signed in as user A, call `GET /api/users/<user B's id>/profile`. It returns B's profile.

## Root cause

The code is the multiplayer beta, which was built so everyone sees everyone. The 0.1 spec made the app single-player, but requirement #1 was owned by "Scope", not by an FR, so nothing changed the code. The routes that are already private use a `DenySelf` check (`TerritoryController.cs:110-121`, `UsersController.cs:55-67`); these routes don't.

## Blast radius

- **Map:** each player sees only their own hexes, not other players' hexes.
- **Live updates:** the phone gets only its own changes. It still receives them on the connection it already opens, but they arrive through its personal group instead of a region group.
- **Leaderboard tab and other players' profiles:** these stop working on current app builds and show an error screen, until the app release that hides them.
- **Old app builds** keep calling `JoinRegion`. It must not throw, or the app's reconnect loop retries forever.
- **In-app theft alert stops.** A player who loses a hex now gets `HexesReleased`, not `HexOwnershipChanged`, so the app's in-app theft alert (`theft_alerts.dart`) no longer fires. The push still arrives. PR 2 removes the in-app alert.
- **Stealing is not changed here.** Ownership still transfers, which is a data-loss bug and gets its own report. Only the push no longer names the other player.
- **Rivals (after 0.1):** the FR that adds rivals decides what becomes public again. This fix adds no switch "for later" (CLAUDE.md, "Stay on the goal").

## Fix plan

Two PRs, server first, so users' data is protected as soon as the server deploys.

**PR 1 — server:**
1. **Live map feed:** the hub requires sign-in. Ownership changes are sent only to the owner's personal group (`user_{id}`), never to a region group. `JoinRegion` still exists but joins nothing, so old apps don't break.
2. **Map area** `GET /api/territories`: returns only the caller's own hexes.
3. **Another player's hexes, user and profile** (`/territories/user/{id}`, `/users/{id}`, `/users/{id}/profile`): use the same self-only check as the private routes. Another id gets 403.
4. **Leaderboard:** returns only the caller's own entry and rank, with no other players.
5. **Stolen-hex push:** says "Some of your hexes were captured.", with no name and no count.
6. **Lost-hexes list** (`/territories/stolen/{me}`): only the cells and times, never who took them. The live feed never sends the new owner the previous owner's id, and a claim reply never names them.

**Not in this fix (each has an owner):** a claim reply still shows that a hex belonged to someone (`WasStolen`, the `cooldown` skip, `StolenFromOthers`). That goes away when stealing is removed, which FR6 owns. The block and report routes answer 404 for an unknown id, so they reveal whether an id exists; FR12 owns them. Ranks and counts still show that other players exist: the caller's own `MyRank` on the leaderboard (kept on purpose above), and `CurrentRank` and `TotalPlayers` on the profile and `Rank` in game-state (`UserService.cs:213-229`, `UsersController.cs:370-383`). FR11 owns them, because the 0.1 profile (#37) has no rank. `TotalHexesStolen` in game-state and in the stats delta go with stealing (FR6). All of these are scenario PRIV-6.

**PR 2 — app:** hide the leaderboard tab, the tap-through to other players' profiles and the in-app theft alert, and move live updates to the personal group.

## Tests that will prove it (each proven red with its fix removed)

| Scenario | Test |
|---|---|
| PRIV-2 | The hub class requires sign-in; an ownership change is sent to `user_{owner}` and never to a region group (fake hub context) |
| PRIV-2 | `JoinRegion` with a valid region neither joins a group nor throws |
| PRIV-1 | Map area: with two players' hexes in the box, the caller gets only their own |
| PRIV-1 | `/territories/user/{other}`, `/users/{other}` and `/users/{other}/profile` return 403; the caller's own id returns 200 |
| PRIV-1 | The leaderboard holds no other player |
| PRIV-1 | The stolen-hex push text contains no other player's name |
| PRIV-1 | The lost-hexes list holds no taker id or claim; a claimed step never names the previous owner |
| PRIV-2 | The new owner's live update carries no previous owner id |

The tests live in `tests/MyLoop.V01.Tests/Bugs/B1/`, which CI runs.
