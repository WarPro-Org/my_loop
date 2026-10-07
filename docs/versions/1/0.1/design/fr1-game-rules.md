# FR1 — Game rules: design

Task: #201. Requirement: `docs/versions/1/0.1/requirements.md` → FR1. FR1 is done (closed again 2026-10-07); the
one-page summary is `docs/versions/1/0.1/records/fr1-game-rules.md` — read that first.

**Status:** written after the code, because Gate 2 was skipped when FR1 was built (see #201). It describes what
was built and the gaps found while writing it; PR 5/9 closed those gaps. An independent audit of all of FR1 then found
more gaps; PR 6/9 recorded them, and PRs 7/9 (server) and 8/9 (app) closed them (see "Work done in PR 7/9" and
"Work done in PR 8/9"). A final audit on master found the last gaps, closed in PR 9/9. The owner approved decisions
D1 and D2.

**FR1 PRs (merge in order):** 1/9 #203 server rules module · 2/9 #210 this design doc · 3/9 #204 server uses the
rules · 4/9 #205 phone uses the rules · 5/9 #214 fixes and contract tests from this doc · 6/9 #215 spec and design
updates from the FR1 audit · 7/9 #216 the audit's server gaps · 8/9 #218 the audit's app gaps (replaced #217, which
was merged into 7/9's branch by mistake and reverted) · 9/9 #219 the final audit's gaps. After the first close-out
(#220) and the scenario table (#222), the 2026-09-29 blind audit reopened FR1: #228 and #229 moved rows to later
FRs and froze the list, #229 fixed the server rows, #230 the phone rows, and #231 closed FR1 again.

## FR1 story in one page

For anyone picking FR1 up without the history (human or AI agent). Facts that must stay true are in the record;
this section is how FR1 got there and what it changed in the way we work.

Key: `#20`-style numbers under **Goal** are requirements in `requirements.md`; numbers in the tables are PRs; the
FR1 task is #201. IDs like `LIFE-10` are edge cases in `docs/scenarios.md`. "Gate 2" is the design-doc step in
CLAUDE.md. A "blind audit" is a check by agents given only the spec and the code, never the design or the PRs.
D1 and D2 are this doc's owner-approved decisions (see "Decisions").

**Goal.** Requirement #20: every number the game is tuned with lives in one versioned settings section, so it can
change after test walks without code changes; anti-cheat numbers never reach the phone (#15).

**What was built (1/9–9/9, Sept 2026).**

| PR | What it did |
|---|---|
| #202 | First try, all of FR1 in one PR (51 files); closed and split |
| #203 | Server Rules module, `GameRules` settings, startup check, `GET /api/rules` |
| #210 | This design doc, written after the code because Gate 2 was skipped; decisions D1 (walk start waits ≤ 3 s) and D2 (mid-walk redeploy accepted until FR9) |
| #204 | Server loop and anti-cheat code read the rules; `AntiCheatConstants.cs` deleted |
| #205 | Phone downloads, saves and uses the rules; a walk keeps its rules |
| #214 | Gaps the design doc found: contract sample, ETag, module boundary, refresh errors, login refresh, D1 wait |
| #215 | First audit's findings written into the spec and this doc (docs only) |
| #216, #218 | First audit's gaps fixed: a missing setting stops the server; walk start asks for rules; captive portal and 503 tests (#217 was merged into the wrong branch, reverted and replaced by #218) |
| #219 | Final audit's gaps: mock-walk tests in CI, FR9 stores a full-rules fingerprint |
| #220 | First close-out: record, CLAUDE.md "Closing an FR" and `Task: #N` rules (closed 2026-09-28) |

**Reopened (2026-09-29).** A blind audit of the whole version found 49 findings; 21 of them landed on FR1, gaps the
earlier FR1 audits had missed (those audits were told what had been built). Main ones: `Infinity` and huge values passed the startup check; no
upper limits; `SkipNeighbors` had no effect; a request stuck in the sign-in step offline blocked every later
refresh; refused replies (403, 404, 429, other 4xx) were untested; the walk-start tests waited in real time. It also
found data-loss and privacy bugs in old beta code outside FR1 (stealing, decay, a startup step that deletes explored
hexes, other players visible) — handled as bug B1 (#224, #225) and moved to FR6, FR7 and FR13 (#228).

**Fixed (2026-09-29 to 2026-10-07).**

| PR | What it did |
|---|---|
| #222 | `docs/scenarios.md` catalogue and this doc's `## Scenarios` table; the 21 gaps became `open #201` rows |
| #228 | Data-loss rows moved to FR6, FR7, FR13; requirement #43 ("no land is ever lost") |
| #229 | Server: `NaN`/`Infinity` rejected, upper limits (≤ 5× shipped), rules built at startup, the rules reply tested over real HTTP. The list was frozen; IN-6/LEG-3 moved to FR6, IN-7 to FR5, DEV-9 to FR3, LEG-5 to FR3/FR5/FR6 |
| #230 | Phone: a rules request gives up after 30 s; refused, stuck and offline-first requests tested; one writer for the saved file; walk-start limit tested in fake time against a written-out 3 s |
| #231 | Close-out again: final audit (`audits/2026-10-07-fr1-final-audit.md`), record, spec, this section |

**What FR1 changed in how we work** (each a rule in CLAUDE.md; some are also checked by "PR rules", the rest by
the independent reviewer and the owner):
- every commit carries `Task: #N`; every FR closes with a record and a final audit (#220), and a blind audit (#222);
- `state-lifecycle-consistency` skill: every reader × every app moment, each test proven red (#206);
- the scenario catalogue every design doc answers in full (#222); `[search]` IDs need a real search, and every
  data-removing file is in `docs/data-removals.md` (#227);
- an early blind audit before each design doc is reviewed, and "triage once, then freeze" when an FR closes — so
  later findings go to the FR that owns the code instead of reopening a finished one (#229);
- a Docs map in CLAUDE.md saying what to read for each activity; a lesson counts only once it is a rule, skill,
  scenario ID or check (#229);
- `solid-architecture` skill required for C# and Dart, and the reviewer works through every gate skill's checklist
  instead of only reading the diff (#229).

**Where to look.** What must stay true: `records/fr1-game-rules.md`. Every edge case and its test: `## Scenarios`
below. Every app moment: "State consistency" below. Audits: `audits/`. Task #201 holds the full check-in log.

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
and the average-speed limit may not be below the per-point limit. Every number setting except `Version` has an
upper limit (at most 5× its shipped value; the rates at most 1), and `NaN` and `Infinity` are rejected. Any failure
stops the server and names the setting. `RulesStartupCheck` builds the rules while the server starts, so nothing
fails later on the first request.

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
| Refused reply (400, 403, 404, 429, 500, 503) | Current rules and saved copy kept; no retry on its own; the next trigger asks again (R3) | one test per status, through the real `ApiService` and Dio, with a positive control (the first request reached the network) — red when refresh retries on its own (shown with an added 5-minute retry timer) |
| First launch, offline, nothing saved, then online | Built-in rules, then the server's on the next refresh, saved (R3) | first launch offline, then refresh — red when an offline start stops later refreshes |
| Request never answers (e.g. sign-in token step stuck offline) | Gives up at 30 s (`rulesRequestLimit`), keeps the rules; the next refresh runs (R3) | fake time: still waiting 1 ms before the limit, done at it; the timed-out request's late answer changes nothing — red when the request has no limit |
| Walk start while the rules request is slow | Starts exactly at the 3 s D1 limit on the rules it has (R1, R2) | fake time against a written-out 3 s: not started 1 ms before, started at it — red when `walkStartRulesWait` or the wait in `startJourney` is longer than 3 s |
| Guest, no sign-in (FR12) | Accepted until FR12: guests don't exist yet, and `GET /api/rules` needs sign-in. FR12 must let a guest get the rules (requirements.md → FR12) | — |
| Any moment, R5 | Accepted: dev-only screen follows the live rules | — |

## Risks

| Risk | Status |
|---|---|
| Anti-cheat numbers leak to the phone | Mitigated: the server's reply must equal the shared five-field sample exactly. `RulesHttpTests` also checks the reply over real HTTP (#229). Limit: its host is set up like `Program.cs` without the other modules, so a JSON option added to `Program.cs` must be added to the test too |
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

## Work done after the blind audit (#228, #229, #230)

1. The list was frozen; rows about code a later FR rebuilds moved to it, each with a spec bullet there (#228:
   data loss to FR6, FR7 and FR13; #229: IN-6 and LEG-3 to FR6, IN-7 to FR5, DEV-9 to FR3, LEG-5 to FR3, FR5, FR6).
2. Server (#229): `NaN` and `Infinity` rejected, upper limits, the rules built at startup, wrong-type values tested,
   the rules reply tested over real HTTP.
3. Phone (#230): a rules request gives up after 30 s; refused replies (400–503), a stuck request, a first launch
   offline, one writer for the saved file and null or wrong-type fields are tested; the walk-start limit is tested in
   fake time against a written-out 3 s.
4. Final audit on master, 2026-10-07: `audits/2026-10-07-fr1-final-audit.md`. The blind audit was not rerun (owner
   decision): it ran on 2026-09-29, and every finding is fixed or moved.

## Scenarios

Every ID in `docs/scenarios.md`, answered for FR1 (game rules). The 2026-09-29 blind audit found 21 gaps
after FR1 was first closed, which reopened it. The list was frozen on 2026-10-07: rows about code a later FR
rebuilds moved to that FR (#228, #229), and nothing found later is added to FR1. The server rows were fixed in
#229 and the phone rows in the PR after it; no row is left `open` with FR1 as owner.

| ID | Status | Evidence |
|---|---|---|
| LIFE-1 | covered | `mobile/test/v0_1/fr1/rules_consistency_test.dart` "a walk started right after launch waits for the saved rules" |
| LIFE-2 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "first launch offline with nothing saved uses the built-in copy, and the next refresh still runs" |
| LIFE-3 | covered | `mobile/test/v0_1/fr1/rules_consistency_test.dart` "a save cut off before it finishes never replaces the saved copy, and the next save works" |
| LIFE-4 | open | FR9: the walk's pinned rules live only in memory and are lost when the app is killed |
| LIFE-5 | n/a | Rules have no background work; they refresh only on app events |
| LIFE-6 | covered | `mobile/test/v0_1/fr1/rules_consistency_test.dart` "returning to the app checks the rules again" |
| LIFE-7 | accepted | "App updated with newer built-in rules": the saved copy wins; approved by the owner in #219 |
| LIFE-8 | covered | `mobile/test/v0_1/fr1/rules_store_test.dart` "a corrupted saved copy is ignored instead of crashing", "a saved copy with an unexpected shape is ignored instead of crashing"; `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "first launch with no internet uses the built-in copy" (nothing loaded falls back to the built-in copy) |
| LIFE-9 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "overlapping refreshes never fetch in parallel or save twice", "a refresh asked for as the last request finishes is never lost"; `mobile/test/v0_1/fr1/rules_store_test.dart` "RulesStore is the only code that touches the saved rules file" |
| LIFE-10 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "a request that never answers gives up at the limit, the next refresh is not blocked, and a late answer is dropped" (the sign-in token step stuck offline). The part about timers piling up doesn't apply: rules run no timers. Other requests' token step is FR3's |
| LIFE-11 | covered | `mobile/test/v0_1/fr1/rules_consistency_test.dart` "starts on the rules it has when its own request fails" |
| NET-1 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "offline with a saved copy uses the saved copy" |
| NET-2 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "a 500 (server error)", "a 503 (server down)" (rules kept, asked again at the next trigger) |
| NET-3 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "a request that never answers gives up at the limit, the next refresh is not blocked, and a late answer is dropped"; `mobile/test/v0_1/fr1/rules_consistency_test.dart` "is not held back longer than the limit when its own request is slow" |
| NET-4 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "a captive portal (Wi-Fi sign-in page sent as HTML)" |
| NET-5 | covered | `mobile/test/v0_1/fr1/rules_consistency_test.dart` "a reconnect after being offline checks the rules again". The 'pending work is sent' part doesn't apply: rules have nothing to send |
| NET-6 | n/a | `GET /api/rules` only reads; no write can be repeated |
| NET-7 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "a request that never answers gives up at the limit, the next refresh is not blocked, and a late answer is dropped", "a refresh after login is not lost behind a signed-out request that got a 401" |
| NET-8 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "a 403 (forbidden)", "a 404 (not found)" (rules kept, no retry on its own). The part about a clear message doesn't apply: a failed rules refresh shows the user nothing, by design |
| NET-9 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "a 429 (too many requests)" |
| NET-10 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "a 400 (bad request)", "a 403 (forbidden)", "a 404 (not found)", "a 429 (too many requests)" |
| NET-11 | n/a | Rules show the user no rejection message |
| AUTH-1 | covered | `mobile/test/v0_1/fr1/rules_consistency_test.dart` "signing out keeps the rules the app already has". Kept vs wiped is documented in this doc's matrix ('Sign out / switch account'); the 'unsent data' part doesn't apply: rules send nothing |
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
| PRIV-6 | n/a | Rules replies are the same for everyone and mention no player |
| PRIV-7 | n/a | The saved rules file holds no player data |
| DEV-1 | n/a | FR1 asks for no permission |
| DEV-2 | n/a | FR1 asks for no permission |
| DEV-3 | n/a | FR1 asks for no permission |
| DEV-4 | n/a | FR1 asks for no permission |
| DEV-5 | covered | `mobile/test/v0_1/fr1/game_rules_provider_test.dart` "broken phone storage still falls back to built-in rules and checks the server"; `mobile/test/v0_1/fr1/rules_consistency_test.dart` "a save cut off before it finishes never replaces the saved copy, and the next save works" (no half-written copy is read). The 'is shown' part doesn't apply to rules: a storage failure falls back without a message, by design (logged as a warning) |
| DEV-6 | n/a | Rules carry no timestamps |
| DEV-7 | n/a | Rules have no background work |
| DEV-8 | n/a | Rules run no timers |
| DEV-9 | open | FR3: the first GPS fix of a walk skips the accuracy threshold (taken before the rules are pinned); moved when the FR1 list was frozen |
| DEV-10 | n/a | GPS filtering beyond the accuracy threshold is FR3's |
| IN-1 | covered | `tests/MyLoop.V01.Tests/FR1/GameRulesTests.cs` "Invalid_value_stops_startup_and_names_the_setting" (Infinity, -Infinity and NaN cases) |
| IN-2 | covered | `tests/MyLoop.V01.Tests/FR1/GameRulesTests.cs` "Invalid_value_stops_startup_and_names_the_setting" |
| IN-3 | covered | `tests/MyLoop.V01.Tests/FR1/GameRulesTests.cs` "Invalid_value_stops_startup_and_names_the_setting" (one step over each limit), "Value_at_its_upper_limit_is_allowed" |
| IN-4 | covered | `tests/MyLoop.V01.Tests/FR1/GameRulesTests.cs` "Missing_setting_stops_startup_and_names_it", "Wrong_type_or_empty_value_stops_startup"; `mobile/test/v0_1/fr1/game_rules_test.dart` "rejects a response with a missing field instead of half-applying it", "a null decimal", "a decimal sent as text" |
| IN-5 | covered | `mobile/test/v0_1/fr1/game_rules_test.dart` "accepts a response with a field it does not know (a newer server)", "rejects a response with a missing field instead of half-applying it" (an older server that lacks a field is rejected, and the current rules are kept). Deploy order is documented in `records/fr1-game-rules.md` (deploy the server before an app release that adds a field) |
| IN-6 | open | FR6: `Loop:SkipNeighbors` has no effect from 0 to `MinPoints` (shipped 10 and 20); FR6 gives it a meaning or removes it; moved when the FR1 list was frozen |
| IN-7 | open | FR5: the hop limit (60 m) is below max speed × interval + drift (71.65 m), so the relation check needs new values; FR5 sets them with the new speed limit; moved when the FR1 list was frozen |
| IN-8 | covered | `tests/MyLoop.V01.Tests/FR1/GameRulesTests.cs` "Rules_are_built_while_the_server_starts_not_on_first_request" |
| SRV-1 | accepted | D2: a redeploy mid-walk judges the rest of the walk by the new rules until FR9 |
| SRV-2 | accepted | Deploy the server before an app release that adds a field (record, "Decisions that must stay true") |
| SRV-3 | n/a | `GET /api/rules` only reads |
| SRV-4 | open | FR7: startup code that rewrites data exists — `DbInitializer.cs:103` deletes every player's explored hexes on a start whenever an owned hex has no explored row for its owner (audit A2) |
| SRV-5 | open | FR13: bot users and bot land are seeded in every environment, Production included (audit A3) |
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
| LEG-1 | open | FR6: stealing and the hourly decay deletion of land still run, against requirement #43 (audit E5) |
| LEG-2 | n/a | The stale comments are corrected (`GameRules.cs`: resume, "(#37)", `SkipNeighbors`; `PathValidationService.cs`: the hop limit); a comment has no test |
| LEG-3 | open | FR6: the `SkipNeighbors` test can only show an effect outside the shipped range, because the setting has none inside it (IN-6); moved when the FR1 list was frozen |
| LEG-4 | n/a | Every FR1 test runs in CI (`ci.yml`: `test/v0_1` and `tests/MyLoop.V01.Tests`) |
| LEG-5 | open | FR3, FR5, FR6: numbers that decide captures are still in code — the phone's noise floor and the first GPS fix (FR3), the smoothness minimums (FR5), the loop overlap (FR6); moved when the FR1 list was frozen |
| LEG-6 | n/a | FR1 has no debug-only path |
| LEG-7 | n/a | No lesson or proposed ADR is about game rules |
| LEG-8 | covered | `mobile/test/v0_1/fr1/rules_consistency_test.dart` "is not held back longer than the limit when its own request is slow", "is not held back longer than the limit by a slow refresh" (fake time against a written-out 3 s: still waiting 1 ms before it, started at it) |
| LEG-9 | n/a | CI's analyze bar isn't specific to FR1 (#221 tracks the process) |
| LEG-10 | n/a | `RulesController` only calls `IRuleSettings` |
| LEG-11 | n/a | FR1 adds no config files |
| LEG-12 | n/a | FR1 adds no user-facing text or achievements |
| DATA-1 | open | FR6, FR7: `docs/data-removals.md` lists every removal path; its `breaks` rows are owned by the FRs that fix them (startup wipe FR7, stealing and decay FR6, account deletion FR12, the phone's point queue FR3) |
| DATA-2 | n/a | searched: `grep -n -i 'ever lost' requirements.md` and `grep -n 'never loses land' requirements.md` — two prose promises (FR6 and FR15), now numbered as requirement #43 |
| API-1 | covered | `tests/MyLoop.V01.Tests/FR1/ContractTests.cs` "Server_sends_exactly_the_shared_client_rules_sample"; `mobile/test/v0_1/fr1/contract_test.dart` "the app knows exactly the fields the server sends". Dates, time zones and ids don't apply: the rules reply has none |
| API-2 | covered | `mobile/test/v0_1/fr1/game_rules_test.dart` "built-in copy matches the server rules in appsettings.json" |
| API-3 | covered | `tests/MyLoop.V01.Tests/FR1/RulesHttpTests.cs` "Rules_reply_over_http_is_exactly_the_shared_sample", "Rules_etag_sent_back_over_http_gives_not_modified" |
| STORE-1 | n/a | FR1 changes nothing store-facing |
