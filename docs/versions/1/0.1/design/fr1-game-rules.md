# FR1 — Game rules: design

Task: #201. Requirement: `docs/versions/1/0.1/requirements.md` → FR1.

**Status:** written after the code, because Gate 2 was skipped when FR1 was built (see #201). It describes what
was built, the gaps found while writing it, and the work still to do (PR 5/5). The owner approved decisions D1 and
D2; the doc itself is approved by merging its PR, before any more FR1 code merges.

**FR1 PRs (merge in order):** 1/5 #203 server rules module · 2/5 this design doc · 3/5 #204 server uses the rules ·
4/5 #205 phone uses the rules · 5/5 phone and server fixes and contract tests from this doc.

## In one paragraph

The server keeps every rule number in one place: the `GameRules` section of `appsettings.json`. It checks the
numbers at startup and won't start if one is missing or wrong. The server's loop and anti-cheat code reads them
through one interface. The phone downloads the few numbers it needs from `GET /api/rules`, saves them, and uses
them for its GPS filter and live loop estimate. Anti-cheat numbers never leave the server.

## Server

**Rules module** — `api/MyLoop.Modules.Rules`, its own project.
- Public: `IRuleSettings` (`Current`, `GetClientRules()`, `ClientRulesTag`), `GameRules` and its sections,
  `ClientRules`, and `AddMyLoopRules()`.
- Meant to be internal: `RuleSettings` (reads the rules once at startup) and `GameRulesValidator` (startup check).
  Both are public today; see "Work still to do".
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
- `refresh()` asks the server with the saved tag. Only one request runs at a time; a refresh asked for during one
  runs once more afterwards. New rules are applied first, then saved. If saving fails, they still apply for this
  session.

**When it refreshes:** app start (always), and through hydration when signed in: login, onboarding (avatar
picker, set home), after each walk, app resume, and reconnect.

**Saved copy:** `game_rules.json` in the app documents folder. Write a temp file, then rename. One save at a
time.

**Readers**
- **R1** GPS accuracy filter during a walk.
- **R2** live loop estimate during a walk.
- R1 and R2 use the rules `JourneyController` fixed at walk start, after `ready`.
- **R3** the rules the app holds (provider and saved file).
- **R4** server loop and anti-cheat code.
- **R5** mock-walk dev screen (watches the live rules).

The built-in copy is version 1 of `appsettings.json`; a test fails if they drift.

## State consistency (every reader × every app moment)

"Red when" = the change that makes the test fail. It was proven by breaking the code on purpose, unless marked
*to prove*.

| Moment | Expected | Test — red when … |
|---|---|---|
| Cold start, before the saved copy loads | A walk waits for it (R1, R2) | walk started right after launch — red when `startJourney` doesn't await `ready` |
| Walk starts while a refresh is running | The walk waits for the running refresh, up to a few seconds (D1), then fixes the rules (R1, R2) | **to add** in 5/5 |
| First launch, offline, nothing saved | Built-in rules (R3) | first launch with no internet — red when refresh doesn't catch the network error |
| Offline / server error / 401 | Current rules kept (R3) | offline with a saved copy — red when the saved copy isn't applied; 401 then login — red when a refresh asked for mid-request joins it instead of running again |
| Offline with an expired sign-in token (non-Dio error) | Current rules kept; later refreshes still work (R3) | **Gap:** only Dio and format errors are caught today. Fix and test in 5/5 |
| Server sends 200 with an unreadable body | Current rules kept (R3) | **to add** in 5/5 |
| Back online / back to the app (signed in) | Rules checked again (R3) | reconnect; resume — red when hydration doesn't call `refresh()` |
| Login | Rules checked again (R3) | **to add** in 5/5 — must go through the real login hydration, not call `refresh()` by hand |
| Sign out / switch account | Rules kept (R3) | sign-out — red when sign-out invalidates `gameRulesProvider` |
| Killed mid-save | Old copy intact; next save works (R3) | save cut off — red when the save writes straight to the file (no temp + rename) |
| Two refreshes at once | One request; none lost (R3) | overlapping refreshes; last-moment refresh — red when calls aren't coalesced / `_inFlight` is cleared late |
| During a walk | R1 and R2 keep the start rules; the next walk uses new ones | walk keeps GPS rules; walk keeps loop rules — red when they read the live rules |
| During a walk, server redeployed with new rules | **Accepted by the owner until FR9 (D2):** the rest of the walk, and saved points sent later, are judged by the new server rules. This breaks requirement #20 ("future walks only") until walks store their rules version | — |
| Killed mid-walk, relaunched | Accepted: a walk doesn't resume; saved points are judged by the server's rules (R4) | — |
| Corrupt saved copy | Built-in rules, still refreshes (R3) | corrupted / wrong shape; broken storage — red when load errors aren't caught |
| Server restart or bad config | Bad numbers stop startup (R4) | server refuses to start — red without `ValidateOnStart` |
| Any moment, R5 | Accepted: dev-only screen follows the live rules | — |

## Risks

| Risk | Status |
|---|---|
| Anti-cheat numbers leak to the phone | Partly mitigated: today's tests only check field names for "Speed", "Violation" and "Drift". **To add:** the exact five-field list |
| Server and phone disagree on field names or types | Mitigated by hand-written tests. **To add:** one shared JSON sample both sides test against |
| Phone mishandles the ETag | **To add:** a test of `getRules` covering quotes, 304, a missing ETag and a weak `W/"…"` ETag |
| Other code uses the module's internal classes | **To add:** make `RuleSettings` and `GameRulesValidator` internal, and a test of the allowed public types |
| A non-Dio error during refresh | **Fix in 5/5:** catch every error in refresh, log it, keep the current rules |
| A walk starts on old rules while a refresh is running | **Fix in 5/5 (D1):** the walk waits for the running refresh, with a time limit |
| A redeploy mid-walk changes how the rest of the walk is judged | Accepted by the owner until FR9 (D2) |
| Speed limit is 30 km/h, not the spec's 20–25 | Accepted: FR5 sets it |

## Decisions (approved by the owner)

- **D1 — walk starts while a refresh is running.** `startJourney` waits for a running refresh for up to a few
  seconds (a named constant), then starts with whatever rules the app has. A walk can only start online, so this
  usually finishes in well under a second.
- **D2 — server rules change mid-walk.** Accepted until FR9, which stores each walk's rules version.

## Work still to do (PR 5/5, after this doc is merged)

1. **Shared contract sample** `tests/contracts/client_rules.json`. The C# test serializes `ClientRules` the way
   the API does and must equal it exactly (same five fields); the Dart test must read it field for field.
2. **Phone ETag handling:** `getRules` sends `If-None-Match` with quotes, returns nothing on 304, strips quotes
   from the tag, and handles a missing ETag and a weak `W/"…"` one.
3. **Module boundary:** `RuleSettings` and `GameRulesValidator` become internal. The test projects build them
   through `AddMyLoopRules` (preferred) or `InternalsVisibleTo`. A test lists the module's allowed public types.
4. **Refresh errors:** catch every error in refresh (fix), and test that a source that throws a non-Dio error keeps the current rules, and the next refresh still
   runs; a 200 with an unreadable body keeps the current rules.
5. **Login trigger:** the real login hydration path starts a rules refresh.
6. **D1:** the walk-start wait, with a test that a walk started during a running refresh uses the refreshed rules,
   and one that a refresh slower than the limit doesn't block the walk.
7. **Prove "red when"** for the cells marked *to prove*.
