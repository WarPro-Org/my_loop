# FR1 — Game rules: design

Task: #201. Requirement: `docs/versions/1/0.1/requirements.md` → FR1.

**Status:** written after the code, because Gate 2 was skipped when FR1 was built (see #201). It describes what
was built and lists the tests still to add. The owner approves it before any more FR1 code merges.

## In one paragraph

The server keeps every rule number in one place: the `GameRules` section of `appsettings.json`. It checks the
numbers at startup and won't start if one is missing or wrong. The server's loop and anti-cheat code reads them
through one interface. The phone downloads the few numbers it needs from `GET /api/rules`, saves them, and uses
them for its GPS filter and live loop estimate. Anti-cheat numbers never leave the server.

## Server

**Rules module** — `api/MyLoop.Modules.Rules`, its own project.
- Public: `IRuleSettings` (`Current`, `GetClientRules()`, `ClientRulesTag`), `GameRules` and its sections,
  `ClientRules`, and `AddMyLoopRules()`.
- Internal: `RuleSettings` (reads the rules once at startup) and `GameRulesValidator` (startup check).
- Other code uses only `IRuleSettings`. Today that is `HexGridService`, `PathValidationService` and
  `RulesController`.

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

**Startup check:** every number must be above 0 (SkipNeighbors may be 0), rates must be above 0 and at most 1,
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

`<tag>` = `{Version}-{first 16 hex chars of SHA-256 of the ClientRules JSON}`, e.g. `1-3fa2…`.

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

The phone rejects a response with a missing or wrongly typed field instead of half-applying it.

## Phone

- `gameRulesProvider` (Riverpod) always holds usable rules: the built-in copy first, then the saved copy, then
  the server's.
- `ready` completes once the saved copy has been read.
- `refresh()` asks the server with the saved tag. Only one request runs at a time; a refresh asked for during one
  runs once more afterwards.
- It refreshes on app start, login, resume and reconnect (hydration).
- New rules are applied first, then saved. If saving fails, they still apply for this session.
- Saved as `game_rules.json` in the app documents folder: write a temp file, then rename, one save at a time.
- `JourneyController` fixes the rules at walk start (after `ready`), and uses them for the GPS accuracy filter and
  the live loop estimate for the whole walk.
- Built-in copy = version 1 of `appsettings.json`; a test fails if they drift.

## State consistency (every reader × every app moment)

Readers: **R1** GPS filter during a walk · **R2** live loop estimate · **R3** the rules the app holds (provider and
saved file) · **R4** server loop/anti-cheat code.

| Moment | Expected | Test (fails when the fix is removed) |
|---|---|---|
| Cold start, before the saved copy loads | A walk waits for it (R1, R2) | `rules_consistency_test`: walk started right after launch |
| First launch, offline, nothing saved | Built-in rules (R3) | `game_rules_provider_test`: first launch with no internet |
| Offline / server error / 401 | Current rules kept (R3) | `game_rules_provider_test`: offline with a saved copy; 401 then login |
| Back online / back to the app | Rules checked again (R3) | `rules_consistency_test`: reconnect; resume |
| Sign in | Rules checked again after login (R3) | `game_rules_provider_test`: refresh after login not lost |
| Sign out / switch account | Rules kept — they aren't tied to a user (R3) | `rules_consistency_test`: sign-out |
| Killed mid-save | Old copy intact; next save works (R3) | `rules_consistency_test`: save cut off |
| Two refreshes at once | One request; none lost (R3) | `game_rules_provider_test`: overlapping refreshes; last-moment refresh |
| During a walk | Start rules kept by R1 and R2; next walk uses new ones | `rules_consistency_test`: walk keeps GPS rules; walk keeps loop rules |
| Killed mid-walk, relaunched | Accepted: a walk doesn't resume; saved points are judged by the server's rules (R4) | — |
| Corrupt saved copy | Built-in rules, still refreshes (R3) | `rules_store_test`: corrupted / wrong shape; provider: broken storage |
| Server restart or config change | New numbers only after redeploy; bad numbers stop startup (R4) | `GameRulesTests`: invalid value / missing section stops startup |
| Mock-walk dev screen | Accepted: dev only, follows live rules | — |

## Risks

| Risk | Status |
|---|---|
| Anti-cheat numbers leak to the phone | Mitigated: `ClientRules` has no anti-cheat fields; tested on both sides |
| Server and phone disagree on field names or types | Mitigated today by hand-written tests; **to add:** one shared JSON sample both sides test against |
| Phone mishandles the ETag (quotes, 304) | **To add:** test of `getRules` request and response handling |
| Other code uses the module's internal classes | **To add:** make `RuleSettings` and `GameRulesValidator` internal, and a test that the module's public types are only the listed ones |
| A rule changes mid-walk | Mitigated: rules fixed at walk start (tested) |
| A walk starts on built-in rules right after launch | Mitigated: walk waits for `ready` (tested) |
| The server doesn't record which rules version judged a walk | Accepted until walk storage (FR9) |
| Speed limit is 30 km/h, not the spec's 20–25 | Accepted: FR5 sets it |

## Tests to add (next FR1 PR, after this doc is approved)

1. **Shared contract sample** `tests/contracts/client_rules.json`. The C# test serializes `ClientRules` the way
   the API does and must equal it; the Dart test must read it field for field.
2. **Phone ETag handling:** `getRules` sends `If-None-Match` with quotes, returns nothing on 304, and strips
   quotes from the tag.
3. **Module boundary:** `RuleSettings` and `GameRulesValidator` become internal (the compiler then blocks other
   code from using them), plus a test listing the module's allowed public types.
