# FR1 — Game rules: design

Task: #201. Requirement: `docs/versions/1/0.1/requirements.md` → FR1. FR1 is done; the one-page summary is
`docs/versions/1/0.1/records/fr1-game-rules.md` — read that first.

**Status:** written after the code, because Gate 2 was skipped when FR1 was built (see #201). It describes what
was built and the gaps found while writing it; PR 5/9 closed those gaps. An independent audit of all of FR1 then found
more gaps; PR 6/9 recorded them, and PRs 7/9 (server) and 8/9 (app) closed them (see "Work done in PR 7/9" and
"Work done in PR 8/9"). A final audit on master found the last gaps, closed in PR 9/9. The owner approved decisions
D1 and D2.

**FR1 PRs (merge in order):** 1/9 #203 server rules module · 2/9 #210 this design doc · 3/9 #204 server uses the
rules · 4/9 #205 phone uses the rules · 5/9 #214 fixes and contract tests from this doc · 6/9 #215 spec and design
updates from the FR1 audit · 7/9 #216 the audit's server gaps · 8/9 #218 the audit's app gaps (replaced #217, which
was merged into 7/9's branch by mistake and reverted) · 9/9 the final audit's gaps.

## In one paragraph

The server keeps every rule number in one place: the `GameRules` section of `appsettings.json`. It checks the
numbers at startup and won't start if one is missing or wrong. The server's loop and anti-cheat code reads them
through one interface. The phone downloads the few numbers it needs from `GET /api/rules`, saves them, and uses
them for its GPS filter and live loop estimate. Anti-cheat numbers never leave the server.

## Server

**Rules module** — `api/MyLoop.Modules.Rules`, its own project.
- Public: `IRuleSettings` (`Current`, `GetClientRules()`, `ClientRulesTag`), `GameRules` and its sections,
  `ClientRules`, and `AddMyLoopRules()`.
- Internal: `RuleSettings` (reads the rules once at startup), `GameRulesValidator` (startup check of the values)
  and `GameRulesPresenceValidator` (startup check that every setting is present). Only the two test projects may build them (`InternalsVisibleTo`), because their tests write rules in code; a test lists
  the module's allowed public types.
- Other code uses only `IRuleSettings`: `HexGridService`, `PathValidationService`, `RulesController`.

**Settings** — `GameRules` in `appsettings.json`:

| Section | Setting | Value | Sent to phone? |
|---|---|---|---|
| — | Version | 1 | yes |
| Loop | ClosureDistanceMeters | 50 | yes |
| Loop | MinPoints | 20 | yes |
| Loop | SkipNeighbors | 10 (0 allowed) | yes |
| Loop | MinAreaSquareMeters | 5000 | no |
| Gps | AccuracyThresholdMeters | 50 | yes |
| AntiCheat | MaxSpeed 8.33 m/s (30 km/h), MaxAverageSpeed 9.0, GpsDriftMargin 30, MaxDistanceBetweenPoints 60, ViolationRate 0.05, SamplingInterval 5, DurationTolerance 0.5, MinBearingStdDev 2.0 | | never |

**Startup check:** every setting must be present (`GameRulesPresenceValidator`; a missing number would otherwise
read as 0), every number must be above 0 (SkipNeighbors may be 0), rates must be above 0 and at most 1,
and the average-speed limit may not be below the per-point limit. Any failure stops the server and names the
setting.

**Changing a rule:** edit `appsettings.json` (or a production override) and redeploy. Bump `Version`. Even
without a bump, the fingerprint changes, so phones still get the new numbers.

## API

`GET /api/rules` — sign-in required.

| Case | Request | Response |
|---|---|---|
| First ask | no `If-None-Match` | `200`, body = `ClientRules`, header `ETag: "<tag>"` |
| Phone is up to date | `If-None-Match: "<tag>"` | `304`, no body |
| Rules changed | `If-None-Match: "<old tag>"` | `200` with the new rules and tag |
| Not signed in | — | `401` |

`<tag>` is an opaque server fingerprint: `{Version}-{16 hex chars}`. The phone stores it and sends it back, and
never builds one itself.

No database, migration or SignalR change.

## Server ↔ phone contract

| C# `ClientRules` | JSON | Dart `GameRules` | Type |
|---|---|---|---|
| `Version` | `version` | `version` | int |
| `LoopClosureDistanceMeters` | `loopClosureDistanceMeters` | `loopClosureDistanceMeters` | double (a whole number is accepted) |
| `MinLoopPoints` | `minLoopPoints` | `minLoopPoints` | int |
| `LoopSkipNeighbors` | `loopSkipNeighbors` | `loopSkipNeighbors` | int |
| `GpsAccuracyThresholdMeters` | `gpsAccuracyThresholdMeters` | `gpsAccuracyThresholdMeters` | double |
| `ETag` header `"<tag>"` | — | `SavedRules.tag` (quotes removed) | string |

Exactly these five fields; anything else in `ClientRules` is a leak. The phone rejects a response with a missing
or wrongly typed field instead of half-applying it.

## Phone

**Providers (Riverpod)**
- `gameRulesProvider` holds the rules the app uses now: the built-in copy first, then the saved copy, then the
  server's. It is never invalidated, not even on sign-out, because rules aren't tied to a user. The app root keeps
  it alive with `ref.listen`.
- `rulesStoreProvider` → `FileRulesStore` (saved copy). `rulesSourceProvider` → `ApiRulesSource` (server).
  Tests replace both.
- `ready` completes once the saved copy has been read.
- `refreshWithin(limit)` starts a refresh unless one is running, then waits for it, at most `limit` (never fails).
- `refresh()` asks the server with the saved tag. Only one request runs at a time; a refresh asked for during one
  runs once more afterwards. New rules are applied first, then saved. If saving fails, they still apply for this
  session.

**When it refreshes:** app start (always), walk start (D1), and through hydration when signed in: login, onboarding (avatar
picker, set home), after each walk, app resume, and reconnect.

**Saved copy:** `game_rules.json` in the app documents folder. Write a temp file, then rename. One save at a
time.

**Readers**
- **R1** GPS accuracy filter during a walk.
- **R2** live loop estimate during a walk.
- R1 and R2 use the rules `JourneyController` pins just before the walk goes live (after the permission dialog and
  first GPS fix), after `ready` and `refreshWithin(walkStartRulesWait)`.
- **R3** the rules the app holds (provider and saved file).
- **R4** server loop and anti-cheat code.
- **R5** mock-walk dev screen (watches the live rules).

The built-in copy is version 1 of `appsettings.json`; a test fails if they drift.

## State consistency (every reader × every app moment)

"Red when" = the change that makes the test fail. Each one was proven by breaking the code on purpose.

| Moment | Expected | Test — red when … |
|---|---|---|
| Cold start, before the saved copy loads | A walk waits for it (R1, R2) | walk started right after launch — red when `startJourney` doesn't await `ready` |
| Walk starts while a refresh is running | The walk waits for the running refresh, up to a few seconds (D1), then fixes the rules (R1, R2) | walk started during a refresh, or one started while the permission dialog is open — red when `startJourney` doesn't wait, or pins the rules before the permission dialog; slow refresh — red when the wait has no limit |
| First launch, offline, nothing saved | Built-in rules (R3) | first launch with no internet — red when refresh doesn't catch the network error |
| Offline / server error / 401 | Current rules kept (R3) | offline with a saved copy — red when the saved copy isn't applied; 401 then login — red when a refresh asked for mid-request joins it instead of running again |
| Offline with an expired sign-in token (non-Dio error) | Current rules kept; later refreshes still work (R3) | failure that isn't a network error — red when refresh doesn't catch every exception |
| Server sends 200 with an unreadable body | Current rules kept (R3) | unreadable reply through the real parser — red when refresh doesn't catch it |
| Back online / back to the app (signed in) | Rules checked again (R3) | reconnect; resume — red when hydration doesn't call `refresh()` |
| Login | Rules checked again (R3) | logging in, through `hydrateAndSyncProfileRank` as the login screen calls it — red when hydration doesn't call `refresh()` |
| Sign out / switch account | Rules kept (R3) | sign-out — red when sign-out invalidates `gameRulesProvider` |
| Killed mid-save | Old copy intact; next save works (R3) | save cut off — red when the save writes straight to the file (no temp + rename) |
| Two refreshes at once | One request; none lost (R3) | overlapping refreshes; last-moment refresh — red when calls aren't coalesced / `_inFlight` is cleared late |
| During a walk | R1 and R2 keep the start rules; the next walk uses new ones | walk keeps GPS rules; walk keeps loop rules — red when they read the live rules |
| During a walk, server redeployed with new rules | **Accepted by the owner until FR9 (D2):** the rest of the walk, and saved points sent later, are judged by the new server rules. This breaks requirement #20 ("future walks only") until walks store their rules version | — |
| Killed mid-walk, relaunched | Accepted: a walk doesn't resume; saved points are judged by the server's rules (R4) | — |
| Corrupt saved copy | Built-in rules, still refreshes (R3) | corrupted / wrong shape; broken storage — red when load errors aren't caught |
| App updated with newer built-in rules | **Accepted by the owner:** the app keeps the saved copy, the last rules the server sent, because the server judges the walk; the walk-start refresh fetches newer ones (D1). Preferring newer built-in rules would go wrong whenever the server is behind the app (an app release before the server deploy, or a server rollback) | — |
| Server restart or bad config | A bad or missing number stops startup (R4) | server refuses to start — red without `ValidateOnStart`; a test per setting that is missing — red without `GameRulesPresenceValidator` (without it, a missing `SkipNeighbors` starts the server); a test per bad value (all 14 settings and the speed pair) — red when that setting's check is removed |
| Server updated between walks, app kept open | The next walk starts on the new rules: starting a walk checks for them, waiting up to the D1 limit (R1, R2). If that request is slow or fails, the walk starts on the rules it has | walk start asks the server itself — red when `refreshWithin` doesn't start a refresh; its own request is slow — red when `refreshWithin` waits for it without the limit; its own request fails — red when the failure reaches `startJourney` |
| Captive portal (HTML reply) / server error (503) | Current rules kept, saved copy untouched (R3). Both reach refresh as a `DioException` | captive portal; server down — through the real `ApiService`, Dio and parser, with a positive control (real rules through the same setup apply) — red when refresh lets the exception escape (e.g. rethrows it) |
| Guest, no sign-in (FR12) | Accepted until FR12: guests don't exist yet, and `GET /api/rules` needs sign-in. FR12 must let a guest get the rules (requirements.md → FR12) | — |
| Any moment, R5 | Accepted: dev-only screen follows the live rules | — |

## Risks

| Risk | Status |
|---|---|
| Anti-cheat numbers leak to the phone | Mitigated: the server's reply must equal the shared five-field sample exactly. Limit: the test uses ASP.NET's default JSON settings, not the real HTTP pipeline; custom JSON options added to the API later would not be caught |
| Server and phone disagree on field names or types | Mitigated: one shared sample, `tests/contracts/client_rules.json`, tested on both sides (same limit as above) |
| A fixed number comes back in the server's loop or anti-cheat code | Mitigated: each of the 12 settings the server's loop and anti-cheat code reads has a "changing it changes the result" test (`ServicesUseRulesTests`, 3 from 3/9 and 9 from 7/9). (The GPS accuracy threshold is checked at startup and passed on to the phone, but no server check uses it yet; its server test comes with FR3.) |
| Dev mock walks stop passing anti-cheat after tuning | Mitigated: the mock-walk tests read the anti-cheat values from `appsettings.json`, and CI and `verify.sh` run them (from 9/9) |
| A rules version doesn't identify one rule set | A setting can change without a version bump (the app still notices through the fingerprint), and the fingerprint covers only the four settings sent to the phone (plus the version). Deferred to FR9: each walk stores a fingerprint of the full rule set, not only the version (requirements.md → FR9) |
| Phone mishandles the ETag | Mitigated: `getRules` tests for quotes, 304, a missing ETag and a weak `W/"…"` one (a weak one was kept with its `W/` and never matched again; fixed) |
| Other code uses the module's internal classes | Mitigated: `RuleSettings` and both validators are internal; a test lists the allowed public types |
| A non-Dio error during refresh | Mitigated: refresh catches every exception and logs the unexpected ones as severe. A bug (a Dart `Error`) still reaches the crash reporter; the rules are kept and later refreshes still run |
| A walk starts on old rules | Mitigated (D1): starting a walk asks the server (or waits for a refresh already running), at most `walkStartRulesWait` (3 s) |
| A redeploy mid-walk changes how the rest of the walk is judged | Accepted by the owner until FR9 (D2) |
| Speed limit is 30 km/h, not the spec's 20–25 | Accepted: FR5 sets it |

## Decisions (approved by the owner)

- **D1 — walk starts while a refresh is running.** `startJourney` waits for a running refresh for up to a few
  seconds (`walkStartRulesWait`, 3 s), then starts with whatever rules the app has. The rules are pinned just before
  the walk goes live, after the permission dialog and first GPS fix, so a refresh during those is not missed. A walk
  can only start online, so the wait usually ends well within a second.
  From 8/9, starting a walk also asks the server for new rules when no refresh is running, and waits the same way
  (`refreshWithin`). Cost: one small request per walk start; the reply is usually "not modified".
- **D2 — server rules change mid-walk.** Accepted until FR9, which stores each walk's rules version
  (requirements.md → FR9).
- **Server GPS-accuracy check:** only the phone drops points below the threshold; the server check comes with FR3
  (requirements.md → FR3).

## Work done in PR 5/9

Six gaps, each with a test proven red when its behaviour is removed: a non-network error during refresh, a walk
started during a refresh (D1), the login trigger, the shared contract sample, the ETag (a weak `W/` one), and the
module's public types. Deviation: tests build the internal
classes via `InternalsVisibleTo`, not `AddMyLoopRules`: they write rules in code; it only reads settings.

## Work done in PR 7/9 (server, from the FR1 audit)

1. A missing setting stops the server (`GameRulesPresenceValidator`). It checks every property of `GameRules` and
   its nested rules classes, so a later number setting is covered without a change. Limit: it treats every class
   as a group of settings, so a later FR that adds a list or text setting must extend it (and test it). Tests: each
   of the 14 settings missing, and a bad value for each.
2. A "changing it changes the result" test for each of the 9 settings the server's loop and anti-cheat code reads
   that had none.

Every new test was shown red when its behaviour is removed: the presence check, each of the 9 new value checks, and
each of the 9 settings replaced by its fixed value.

## Work done in PR 8/9 (app, from the FR1 audit)

1. Starting a walk asks the server for new rules when no refresh is running (`refreshWithin`), and waits up to the
   D1 limit; tested through `startJourney`, including when that request is slow or fails.
2. Captive-portal HTML and 503 tests through the real `ApiService` and Dio. The sign-in interceptor is removed in
   these tests: it needs Firebase, and would otherwise fail the request before it reaches the fake network.
3. Mock-walk tests read the anti-cheat values from `appsettings.json` instead of copies (red when a value there is
   tightened, e.g. the average-speed limit set to 1 m/s).

Every new test was shown red when its behaviour is removed: the walk-start refresh, its limit and its error
handling, and refresh's catch (captive portal, 503).

## Work done in PR 9/9 (from the final audit on master)

1. The "app updated with newer built-in rules" moment is in the matrix, accepted by the owner: the app keeps the
   last rules the server sent. (Preferring the newer built-in rules was tried and dropped in review: it goes wrong
   whenever the server is behind the app.)
2. CI and `scripts/verify.sh` run `mobile/test/mock_walk_engine_test.dart` too, so the mock-walk check against
   `appsettings.json` guards every change.
3. Spec: FR9 stores a fingerprint of the full rule set per walk, because a version number alone doesn't identify one.

## Scenarios

Every ID in `docs/scenarios.md`, answered for FR1 (game rules). The rows marked `open #201` were found by the
2026-09-29 blind audit after FR1 was closed. They reopen FR1, which is not done until they are fixed.

| ID | Status | Evidence |
|---|---|---|
| LIFE-1 | covered | `mobile/test/v0_1/fr1/rules_consistency_test.dart` "a walk started right after launch waits for the saved rules" |
| LIFE-2 | open | #201: the built-in copy is used offline on first launch (`game_rules_provider_test.dart`), but no test checks that the next refresh still runs |
| LIFE-3 | covered | `mobile/test/v0_1/fr1/rules_consistency_test.dart` "a save cut off before it finishes never replaces the saved copy" |
| LIFE-4 | open | FR9: the walk's pinned rules live only in memory and are lost when the app is killed |
| LIFE-5 | n/a | Rules have no background work; they refresh only on app events |
| LIFE-6 | covered | `mobile/test/v0_1/fr1/rules_consistency_test.dart` "returning to the app checks the rules again" |
| LIFE-7 | accepted | "App updated with newer built-in rules": the saved copy wins; approved by the owner in #219 |
| LIFE-8 | covered | `mobile/test/v0_1/fr1/rules_store_test.dart` "a corrupted saved copy is ignored instead of crashing", "a saved copy with an unexpected shape is ignored" |
| LIFE-9 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "overlapping refreshes never fetch in parallel or save twice"; `mobile/test/v0_1/fr1/rules_store_test.dart` "overlapping saves never fail and the last one wins on disk" |
| LIFE-10 | open | #201: an expired token offline makes a request hang in the sign-in interceptor, and the stuck refresh blocks all later ones |
| LIFE-11 | covered | `mobile/test/v0_1/fr1/rules_consistency_test.dart` "starts on the rules it has when its own request fails" |
| NET-1 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "offline with a saved copy uses the saved copy" |
| NET-2 | open | #201: the 503 case keeps the rules (`game_rules_provider_test.dart`), but no test checks that a later refresh runs |
| NET-3 | open | #201: walk start waits on a refresh already running, which may be stuck on a dead socket |
| NET-4 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "a captive portal (Wi-Fi sign-in page sent as HTML)" |
| NET-5 | covered | `mobile/test/v0_1/fr1/rules_consistency_test.dart` "a reconnect after being offline checks the rules again" |
| NET-6 | n/a | `GET /api/rules` only reads; no write can be repeated |
| NET-7 | open | #201: same interceptor hang as LIFE-10 (the 401 after login is covered in `game_rules_provider_test.dart`) |
| NET-8 | open | #201: no test sends a 403 or 404; the catalogue also asks for no endless retry |
| NET-9 | open | #201: no test sends a 429 or checks that it is retried later |
| NET-10 | open | #201: no test sends a 4xx (only a 200 with a broken body) to prove the rules and saved copy are kept and a later refresh asks again |
| NET-11 | n/a | Rules show the user no rejection message |
| AUTH-1 | covered | `mobile/test/v0_1/fr1/rules_consistency_test.dart` "signing out keeps the rules the app already has" |
| AUTH-2 | covered | `mobile/test/v0_1/fr1/rules_consistency_test.dart` "logging in checks the rules again" |
| AUTH-3 | n/a | Rules are the same for every user; nothing is cached per account |
| AUTH-4 | open | FR12: guests can't fetch the rules (`GET /api/rules` needs sign-in) |
| AUTH-5 | n/a | A walk's pinned rules don't depend on the account |
| AUTH-6 | n/a | FR1 creates no accounts |
| PRIV-1 | n/a | Rules are the same for everyone and hold no user data |
| PRIV-2 | n/a | FR1 has no real-time channel |
| PRIV-3 | n/a | Rules logs hold only versions and errors, no personal data |
| PRIV-4 | n/a | The saved rules file holds no user data |
| PRIV-5 | n/a | FR1 writes no user data |
| DEV-1 | n/a | FR1 asks for no permission |
| DEV-2 | n/a | FR1 asks for no permission |
| DEV-3 | n/a | FR1 asks for no permission |
| DEV-4 | n/a | FR1 asks for no permission |
| DEV-5 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "broken phone storage still falls back to built-in rules and checks the server". "Shown" doesn't apply to rules: a storage failure falls back without a message, by design (logged as a warning) |
| DEV-6 | n/a | Rules carry no timestamps |
| DEV-7 | n/a | Rules have no background work |
| DEV-8 | n/a | Rules run no timers |
| DEV-9 | open | #201: the first GPS fix of a walk skips the accuracy threshold (taken before the rules are pinned) |
| DEV-10 | n/a | GPS filtering beyond the accuracy threshold is FR3's |
| IN-1 | open | #201: `Infinity` passes `GameRulesValidator` |
| IN-2 | covered | `tests/MyLoop.V01.Tests/FR1/GameRulesTests.cs` "Invalid_value_stops_startup_and_names_the_setting" |
| IN-3 | open | #201: rule values have no upper bounds |
| IN-4 | open | #201: a missing field is rejected on both sides (`GameRulesTests.cs`, `game_rules_test.dart`); null and wrong-type fields have no test |
| IN-5 | covered | `mobile/test/v0_1/fr1/game_rules_test.dart` "accepts a response with a field it does not know" |
| IN-6 | open | #201: `Loop:SkipNeighbors` has no effect from 0 to `MinPoints`; its test uses 40 |
| IN-7 | open | #201: `MaxDistanceBetweenPoints` isn't checked against speed × interval + drift |
| IN-8 | open | #201: `RuleSettings` is built on first use, so a bad value found only then gives 500s |
| SRV-1 | accepted | D2: a redeploy mid-walk judges the rest of the walk by the new rules until FR9 |
| SRV-2 | accepted | Deploy the server before an app release that adds a field (record, "Decisions that must stay true") |
| SRV-3 | n/a | `GET /api/rules` only reads |
| SRV-4 | n/a | FR1 changes no schema |
| SRV-5 | n/a | FR1 seeds nothing |
| SRV-6 | n/a | The reply is five fixed fields |
| SRV-7 | n/a | `GET /api/rules` only reads |
| SRV-8 | n/a | FR1 keeps no totals |
| GAME-1 | n/a | FR1 only supplies the numbers; loop rules are FR6's |
| GAME-2 | n/a | FR1 only supplies the numbers; loop rules are FR6's |
| GAME-3 | n/a | FR1 only supplies the numbers; loop rules are FR6's |
| GAME-4 | n/a | FR1 only supplies the numbers; noise filtering is FR3's |
| GAME-5 | n/a | FR1 only supplies the numbers; loop limits are FR6's |
| GAME-6 | n/a | FR1 only supplies the numbers; crossing detection is FR6's |
| GAME-7 | n/a | Gaps are FR4's |
| GAME-8 | n/a | Batch steps are FR3's and FR5's |
| GAME-9 | n/a | Timestamps are FR3's and FR5's |
| GAME-10 | n/a | Section rejection is FR5's |
| GAME-11 | n/a | Capture is FR6's |
| GAME-12 | n/a | Exploration is FR7's |
| GAME-13 | open | FR8: the preview sends 500 points while the server allows 10,000, and the earth radius differs between phone and server |
| GAME-14 | n/a | The end-of-walk result is FR2's and FR8's |
| GAME-15 | n/a | Pause and auto-end are FR2's |
| GAME-16 | n/a | Exploration is FR7's |
| CHEAT-1 | n/a | Claim checks are FR5's and FR6's |
| CHEAT-2 | n/a | Timestamp checks are FR5's |
| CHEAT-3 | n/a | Step checks are FR5's |
| CHEAT-4 | open | FR5: the limit is still 30 km/h, not 20–25 km/h (kept by the owner until FR5) |
| CHEAT-5 | n/a | Replay detection is FR5's |
| CHEAT-6 | covered | `tests/MyLoop.V01.Tests/FR1/ClientRulesTests.cs` "Client_rules_contain_no_anti_cheat_numbers"; `mobile/test/v0_1/fr1/game_rules_test.dart` "the app never knows anti-cheat numbers" |
| LEG-1 | n/a | The old anti-cheat constants were deleted (#204); no old rules code runs |
| LEG-2 | open | #201: stale comments in `GameRules.cs` ("resuming after a pause", "(#37)", the `SkipNeighbors` description) |
| LEG-3 | open | #201: the `SkipNeighbors` test proves an effect only outside the shipped range |
| LEG-4 | n/a | Every FR1 test runs in CI (`ci.yml`: `test/v0_1` and `tests/MyLoop.V01.Tests`) |
| LEG-5 | open | #201: numbers that decide captures are still in code (loop overlap, smoothness minimums, the phone's noise floor), and the first GPS fix bypasses the rules |
| LEG-6 | n/a | FR1 has no debug-only path |
| LEG-7 | n/a | No lesson or proposed ADR is about game rules |
| LEG-8 | open | #201: the walk-start tests wait in real time and check 5 s, not 3 s |
| LEG-9 | n/a | CI's analyze bar isn't specific to FR1 (#221 tracks the process) |
| LEG-10 | n/a | `RulesController` only calls `IRuleSettings` |
| LEG-11 | n/a | FR1 adds no config files |
| API-1 | covered | `tests/MyLoop.V01.Tests/FR1/ContractTests.cs` "Server_sends_exactly_the_shared_client_rules_sample"; `mobile/test/v0_1/fr1/contract_test.dart` "the app knows exactly the fields the server sends" |
| API-2 | covered | `mobile/test/v0_1/fr1/game_rules_test.dart` "built-in copy matches the server rules in appsettings.json" |
| API-3 | open | #201: the contract test serialises in the test, not through the real HTTP pipeline |
| STORE-1 | n/a | FR1 changes nothing store-facing |
