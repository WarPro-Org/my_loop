# FR2 — Walk session: design

Task: #236. Requirement: `docs/versions/1/0.1/requirements.md` → FR2. Gate 1 answers for every scenario ID: the
comment "Gate 1 — scenario answers" on #236. Early blind audit: `audits/2026-10-14-fr2-early-blind-audit.md`.

**Status:** Gate 2 draft, waiting for the owner. The ten owner decisions below (O1–O10) must be answered before this
doc merges; merging it is the owner's approval (CLAUDE.md, Gate 2).

## FR2 in plain words

### Where we are

- **FR1 (done)** put every game number in one rulebook on the server. The phone downloads the numbers it needs and a
  walk keeps the same numbers from start to end.
- **FR2 Gate 1 (done, 2026-10-14)** agreed what a walk is. The owner made it simpler than the old plan: there is no
  Pause, and a walk that stops by accident ends where it stopped instead of trying to come back.
- **This doc (Gate 2)** says how to build it, and lists what the early blind audit found in today's code.

### What FR2 covers

1. **Start.** A walk starts only when you tap "Start walk". The app needs "While using" location, never "Always".
   Notifications are asked for but optional.
2. **Stop.** Stop asks "End walk?", and warns you if your current loop isn't closed yet.
3. **Forgotten walks end on their own.** If you drive off (faster than 35 km/h for 3 minutes) or leave the phone
   still (within 50 m — 75 m with O3 — for 30 minutes), the walk ends, its end time goes back to when that started,
   and you're told.
4. **Accidents end the walk where it stopped.** If the app is closed (the phone kills it, it crashes, the phone
   restarts), location is removed, GPS is turned off, or you sign out, the walk ends at its last point. Your trail
   up to that point is kept; for a closed app, the land inside loops you closed waits for FR6 (owner decision O1).
5. **A walk diary.** From the moment you tap Start, the phone writes down what happened to the walk and why — no
   locations, only events and times. It's how we find out later why a walk went wrong. FR3 sends it to the server.

**Not in FR2:** sending GPS points and diaries (FR3), tracking gaps and the safety alarm (FR4), cheat checks (FR5),
the capture rule (FR6).

### What a normal user will notice

| Situation | Today | After FR2 |
|---|---|---|
| Opening the walk map with location refused | The app may throw you into Settings | The app explains how to allow location; you choose to open Settings |
| Tapping Stop by mistake | The walk ends at once | "End walk?" — tap "Keep walking" to carry on |
| Stopping before a loop is closed | No warning | "Your current loop isn't closed; its land won't be captured" |
| Forgetting to stop and getting in a car | The walk runs on, sending rejected points | The walk ends after 3 minutes above 35 km/h; "Walk saved" notification |
| Leaving the phone on a table | The walk runs for hours | Ends after 30 minutes; its time and distance don't include the 30 minutes |
| Phone kills the app mid-walk | The walk is gone without a word | Next launch: "Your walk ended early at 10:42"; the trail up to then is kept (loop land: O1) |
| Turning off location or GPS mid-walk | "Recording" carries on with nothing recorded | The walk ends and is saved, and the app says why |
| Signing out mid-walk | The walk is thrown away | The walk ends and is saved; its closed loops are sent first when online (O9) |
| A walk that went wrong | No way to find out why | The diary shows every event; the owner can read it in a debug build now, and on the server after FR3 |

Things a user will **not** get: no Pause button, and a closed app never resumes the walk.

## Decisions waiting for the owner

Each one comes from the early blind audit. The recommendation is what this doc is written for.

| # | Question | Recommendation | Why |
|---|---|---|---|
| O1 | A closed app ends the walk at its last point (#45), but today the land inside closed loops is sent only when Stop is tapped, from a path kept in memory. Keep it, or accept the loss for now? | **Accept until FR6.** Trail hexes are kept (they're sent while walking); the land inside loops closed before the app was closed is lost until FR6, whose server finds loops in the points it already stored. FR2 doesn't build a path store that FR6 makes useless | Saving the full path is FR3's "every point saved" work, and FR6 removes the need |
| O2 | Moving the end time back after a drive or a still stretch: the points sent during that stretch stay on the server | **Accept.** Driving points above 30 km/h are already rejected by the server's speed check; a still phone adds almost no points (the noise floor drops them). The phone takes the stretch out of the walk's time, distance and path | Undoing sent points needs server work that FR5/FR9 own |
| O3 | The still rule's 50 m equals the GPS accuracy threshold (50 m), so two allowed fixes can be 100 m apart and jitter keeps resetting the 30-minute count. And a radius alone can't tell a still phone from laps of a small block | **Raise the still radius to 75 m**, measured from the average of the stretch's fixes, with the startup check "at least 1.5× the accuracy threshold" (the two are then tuned together). **Add a fifth setting, `StillMaxWalkedMeters` = 500:** the stretch only counts as still if the walk's recorded path grew by less than 500 m in it. One fix outside the radius doesn't restart the count; two in a row do | Jitter from an indoor phone should stay inside 75 m of the average; laps add about 2.5 km of path in 30 minutes. **Risk:** how much path indoor jitter adds past the 10–25 m noise floor is unproven — if it reaches 500 m, a forgotten phone indoors never ends as still (the 30-minute no-GPS rule doesn't help, because fixes keep coming). So the number is checked against a real indoor trace before PR 6/7 merges; 1,000 m is the fallback, still well under laps |
| O4 | A failed account deletion still wipes the walk's unsent points (audit W13) | **Fix in FR2:** stop the walk first as today, but clear its points and diary only after the server says the account is gone | FR2 touches this path anyway; the user keeps the account, so they keep the walk |
| O5 | Notification permission is already asked at login (for push), and iOS shows the prompt once | **Change the spec to "asked at the first walk start if it hasn't been asked yet"** | The login ask stays until FR11 decides notifications; asking twice isn't possible on iOS |
| O6 | Precise location turned off mid-walk: every fix is silently dropped and the walk would end 30 minutes later as "still" | **End the walk at once, saved, with the reason "precise location turned off"** — the same as location removed (#42) | The walk can't capture anything without precise location; a wrong "you stopped moving" is worse |
| O7 | GPS switched off mid-walk, even by a quick slip in the quick settings | **End the walk at once** (the spec's "GPS turned off mid-walk counts as removed") | Strict and simple, as decided for the closed app |
| O8 | The iOS privacy manifest is missing (an upload is rejected without it), FR2 adds a notification package, and the system location prompt appears with no explanation | **In FR2's permissions PR:** add `PrivacyInfo.xcprivacy`; the "While using" purpose string says tracking goes on with the screen off; a one-screen explanation before the first system location prompt ("MyLoop uses your location only while you walk"); `docs/compliance/` updated to match FR2 (it still says to drop background tracking). The unused "Always" purpose string is removed only if the geolocator iOS code doesn't reference the "Always" API (checked first; otherwise kept with honest wording, so the upload doesn't warn) | FR2 is the first FR to touch permissions and add an SDK; App Store rules (STORE-1); the privacy-manifest lesson in `docs/learnings/phase-1.md` |
| O9 | Sign-out "ends and saves the walk" (#46), but today sign-out deletes the walk's unsent points; offline, the whole trail since the last send is lost | **Keep the step-claim queue file at sign-out** (it is already one file per account since bug #110, so the next account can't send it). The points go when that account signs in again (FR3 sends at launch). `ended signedOut` is written online and offline. Account deletion still clears it (O4). The register row for `journey_controller.dart` changes from "breaks #9, FR3" for this path | #46 says "saves"; clearing was only needed while the file was shared between accounts |
| O10 | After the app update, the saved rules copy has no auto-end fields | **Keep its server values and tag and fill only the four (five with O3) new fields from the built-in copy**, instead of throwing it away; the diary's `started` line records the auto-end values themselves, because the kept tag then doesn't name them. The FR1 record's "Saved copy" row gets this line | Keeps the FR1 decision "after an app update the phone keeps the last rules the server sent" |

If O1, O3, O5, O6 or O9 is approved, the spec and #236 are updated in the same PR as this doc, and O1 adds a line to
FR6 ("loops closed before a closed app ended the walk are captured from the stored points").

## Decisions already approved (Gate 1)

The spec's FR2 section has them in full: no Pause (#32 dropped); diary #44; closed app ends the walk #45; sign-out
ends and saves the walk #46; auto-end at 35 km/h for 3 min or still for 30 min, four settings, end time moved back,
counts on the phone's elapsed clock; "While using" only; Stop confirms; the startup checks for the vehicle speed
and the still radius; a diary write failure never blocks a walk; debug-only diary viewer.

## How it works — phone

### One owner for a walk

Today the end of a walk is split: `JourneyController.stopJourney` stops GPS, and the journey screen
(`_onStopCapture`) sends the loop claim and shows the result. An auto-end or a lost permission happens with the
screen closed or the app in the background, so it can't use the screen's code (audit P18).

- `JourneyController.endWalk(WalkEndReason reason, {DateTime? endAt})` becomes the **only** way a walk ends. It:
  1. stops GPS and the walk's timers (sync, first, so nothing more is recorded);
  2. writes the diary's end line with the reason;
  3. trims the path and distance back to `endAt` when given (auto-end). To make this possible the controller keeps
     each recorded path point's GPS time next to the path, and the walk's start time is the first accepted fix's GPS
     time, so start and end come from the same clock (audit W21, P25);
  4. sends the loop claim when the phone's own loop check found a loop **or** the server preview did (today it's
     the preview only, audit W11), then drains the queue once with `drainNow` (today's `drainBeforeCapture`, which
     has no caller, is removed — audit W32);
  5. publishes the result in `lastWalkEndProvider` (below) for whichever screen is showing.
- Callers: Stop (after the dialog), auto-end, location removed / GPS off / precise off, sign-out, and the closed-app
  check at launch (which only writes the diary and publishes the result — the GPS is already gone).
- `WalkEndReason`: `stoppedByUser`, `autoEndedVehicle`, `autoEndedStill`, `noGps`, `locationRemoved`, `gpsOff`,
  `preciseLocationOff`, `appClosed`, `signedOut`, `signedOutForced`. Each has one user message; none says
  "anti-cheat" (NET-11).
- The short-walk notice ("Walk a bit more") stays, but the walk still gets its diary lines (audit W10).
- `startJourney` refuses while a walk is starting or running (audit W5), and a start that fails at any step goes back
  to "not walking" with the diary line "start failed: <reason>" (audit W2, W3, W4). The walk id and the diary's
  "start tapped" line are written first, before the reachability check, permission and first fix.
- One `StepClaimQueue` per account, owned by the controller across walks, so a stopped walk's last batch can't
  overwrite the next walk's points (audit W22). The queue's other problems — a failed rewrite sending points twice and
  leaving a `.tmp` file (audit W25), and lines with no format version (audit W26) — are FR3's, which rebuilds sending.
- The app version comes from the new package `package_info_plus` (audit W1).

### The walk diary (#44)

- **File:** `walk_diary_<userId>.jsonl` in the app documents folder, one per account, using the queue's file-name
  rule. `userId` is the server's GUID (`user_state.dart:93`), only hex digits and dashes, so the `a.b`/`a_b`
  collision of audit W27 can't happen; a test pins it.
- **One writer:** `WalkDiaryStore`, one instance per account from `walkDiaryStoreProvider`, with one write lock.
  Every caller goes through it (audit W23).
- **Line format** (append only, one JSON object per line, `\n` written with the line):

  | Field | Type | Example |
  |---|---|---|
  | `v` | int | `1` — format version; a reader skips lines with a newer `v` it doesn't know |
  | `walkId` | string (UUID) | the walk's id, also the server's `WalkSessionId` |
  | `at` | string, UTC ISO 8601 | `2026-10-14T10:42:05.123Z` (phone clock) |
  | `event` | string | `startTapped`, `started`, `startFailed`, `alive`, `ended`, `gpsError`, `diaryDamaged` |
  | `detail` | object | per event, below; never coordinates |

  - `started`: `rulesVersion`, `rulesTag` (the FR1 fingerprint, so a changed value without a version bump is still
    known — audit S17, W29), the auto-end values the walk pinned (O10), `appVersion`, `permission`
    (`whileUsing`/`always`), `precise` (bool), `notifications` (`granted`/`denied`/`notAsked`).
  - `alive`: `lastFixAt` (GPS time of the last accepted fix). Written at most once a minute while walking, so a
    closed app's end time is known within a minute (audit W19). A one-hour walk writes about 60 lines.
  - `ended`: `reason` (a `WalkEndReason`), `endAt` (GPS time of the walk's last fix), and for auto-end the setting
    values that ended it.
  - `startFailed`: `reason` (`offline`, `permissionDenied`, `permissionDeniedForever`, `restricted`, `gpsOff`,
    `noFix`, `diskError`). A start with no signed-in account has no diary to write to: it is logged and the
    start refused (audit W3).
- **A half-written line** (app killed mid-write) is skipped on read; the next write starts with `\n` if the file
  doesn't end with one, so it never joins a broken line (audit W24).
- **Write fails** (phone full): the line stays in memory and is written before the next one; the failure is logged
  and shown in the debug viewer; the walk carries on (DEV-5).
- **Kept until:** the account is deleted (FR2), or the server confirms it has the lines (FR3). Sign-out keeps it.
- **Debug viewer:** route `/dev/walk-diary`, added only `if (kDebugMode)` like `/dev/mock-walk`, with a button on the
  journey screen in debug builds. It lists walks, their events and any write failures or damaged lines.

### Closed app (#45)

- At launch (and at login), once the signed-in account is known, the diary is read. Both can fire on a cold start,
  so the check runs once at a time through the diary's lock, and a walk that already has its `ended` line is
  skipped. A walk with `startTapped` or `started` and no `ended` line was closed mid-walk.
- `endWalk(appClosed)` writes `ended` with `endAt` = the last `alive` line's `lastFixAt` (or the start time if there
  is none, which gives an empty walk the diary still records — audit P27).
- If location permission is now off, the reason is `locationRemoved` instead, and if only approximate location is
  allowed, `preciseLocationOff`: Android stops the app when either is changed, so this is the only place those cases
  can be seen (audit P2).
- The user sees "Your walk ended early at 10:42" once, through `lastWalkEndProvider`.
- The killed walk's unsent points stay in the queue and go with the next walk's sending, as today (FR3 sends them at
  launch). The land inside its loops: owner decision O1.

### Auto-end (#34)

`AutoEndDetector` — a plain Dart class with no plugins, fed by the controller, reading the walk's pinned rules
(never the live provider — audit S23). It only uses fixes that pass the GPS accuracy threshold, with the fix's own
GPS time (`Position.timestamp`), never `pos.speed` (it reads 0 when missing — audit P19).

- **Vehicle:** over the last `VehicleSeconds`, the walk's recorded path (the points the noise floor kept, with their
  GPS times) grew faster than `VehicleSpeedMetersPerSecond` on average, and the window really spans that long. Using
  the recorded path, not every raw fix, keeps a jittering still phone from adding up fake distance (a test with a
  jittering still phone); one GPS jump can't do it alone (DEV-10). Hops with equal or backwards times are skipped
  (GAME-9). A tunnel, or the plugins sending only the newest fix of a batch (audit P15), gives one long hop, which
  still counts at its true average speed. `endAt` = the last point before the window.
- **Still:** for the last `StillSeconds`, every accepted fix is within `StillRadiusMeters` of the average of those
  fixes and the recorded path grew by less than `StillMaxWalkedMeters` (O3); one fix outside is ignored, two in a row
  restart the count. `endAt` = the last point before the still stretch began, as the spec says.
- **No GPS:** no accepted fix at all for `StillSeconds` → `noGps`, so a dead GPS, a silent Android stream (audit P6)
  or a lost precise location isn't reported as "you stopped moving" (audit P23). A start whose first fix never comes
  fails as `startFailed noFix` (today's 15 s limit).
- **Clock:** the counts use a monotonic `Stopwatch` while the app runs, and one one-shot `Timer` set to the next
  deadline (no new periodic timer — DEV-8). After the phone suspends the app (possible on iOS when no fix arrives —
  audit P14, UNVERIFIED), the check runs again on the next fix, on resume and at launch; because `endAt` comes from
  fix times, a late check still ends the walk at the right time — only the notification is late.
- **Ending:** `endWalk(autoEndedVehicle | autoEndedStill | noGps, endAt: …)`, then the notification.

### Permissions (#42)

`LocationService` changes; `ILocationSource`-style interface kept so tests swap it.

- `checkAccess()` returns one of: `granted`, `approximateOnly`, `denied`, `deniedForever`, `restricted`, `gpsOff`.
  It never opens Settings (audit W6). The screen shows a plain message and, for `deniedForever` and `gpsOff`, an
  "Open settings" button the user taps; `restricted` says location is blocked on this phone (audit P8).
- Opening the walk map only reads the current access and the last known position; it asks for permission only when
  the user taps "Start walk".
- During a walk:
  - **stream error:** run `checkAccess()`. Location off → `endWalk(locationRemoved)`; GPS off →
    `endWalk(gpsOff)` (O7); precise off → `endWalk(preciseLocationOff)` (O6); still granted → diary `gpsError` and
    carry on (iOS sends one generic error for all of these — audit P3);
  - **stream ends** (`onDone`): treated like an error;
  - **back to the app** (`AppLifecycleListener.onResume`): `checkAccess()`, same outcomes (LIFE-6).
- `requestPermission` no longer logs that "Always" is needed (audit W7).
- FR2 never restarts the location stream: GPS off ends the walk (O7). So Android 14's rule against starting a
  location service from the background (audit P13) can't be hit.
- Offline is checked after permission, so an offline user without permission hears about permission first (audit
  P10). Starting offline stays blocked until FR3.

### Notifications

- New package `flutter_local_notifications` behind a small `WalkEndNotifier` interface (one real, one fake for
  tests). Android: `POST_NOTIFICATIONS` declared in the app's own manifest (today it comes only from
  firebase_messaging — audit P11), one channel "Walk updates", the app's small icon. iOS: set up so it doesn't take
  over firebase_messaging's handling (checked on a real phone before merge — audit P16, UNVERIFIED).
- At walk start, if notification permission was never asked, ask it (O5). Refusing never blocks the walk.
- Android 13+ hides the tracking notification when notifications are refused (audit P12, UNVERIFIED); tracking
  still works and the status bar shows location in use. Accepted.
- Shown only when the app is in the background; in the app, `lastWalkEndProvider` shows the message on the home and
  journey screens until the user dismisses it (audit P17).

### Sign-out and account deletion (#46)

- **Sign-out:** `abandonForSignOut` first calls `endWalk(signedOut)` when a walk is running — online and offline.
  Online it also sends the loop claim and drains once. Then it tears down as today, except that the account's
  step-claim queue file is kept (O9); the diary file is kept.
- **Forced sign-out:** no token, so only the diary line (`signedOutForced`); the teardown follows.
- **Account deletion:** stop the walk (GPS and drain) first as today; only after the server confirms the deletion,
  clear the queue and delete the diary file (O4). A failed deletion keeps both.
- A signed-out account's diary waits on the phone until that account signs in again and FR3 sends it; a diary is
  small (about one line a minute of walking). Files of accounts that never return: FR3 decides (audit W28).

### Stop dialog (#33)

- "End walk?" with "End" and "Keep walking".
- The warning comes from the phone's own loop check, so it works offline: the controller keeps the path index where
  the phone last found a loop; if points were walked after it, the dialog adds "Your current loop isn't closed. Land
  inside it won't be captured." (audit W35).

## How it works — server

### Settings

New section `AutoEnd` in `GameRules` (its own section, never inside `AntiCheat` — audit S16). Plain numbers with the
unit in the name, never `TimeSpan` (audit S2):

| Setting | Shipped | Allowed | Sent to phone |
|---|---|---|---|
| `AutoEnd:VehicleSpeedMetersPerSecond` | 9.72 (35 km/h) | above 0, at most 16.67 (60 km/h); above both anti-cheat speeds | yes |
| `AutoEnd:VehicleSeconds` | 180 | 60 to 600 | yes |
| `AutoEnd:StillRadiusMeters` | 75 (O3; 50 if O3 is refused) | at most 300 (250 if O3 is refused, FR1's 5× rule); at least 1.5× `Gps:AccuracyThresholdMeters` (O3) | yes |
| `AutoEnd:StillMaxWalkedMeters` | 500 (O3) | 100 to 2000; above `StillRadiusMeters` | yes |
| `AutoEnd:StillSeconds` | 1800 | 300 to 3600 | yes |

- `Version` goes from 1 to 2 (audit S17).
- The upper limits are tighter than FR1's "5× shipped" on purpose: 5× would allow 175 km/h or 150 minutes, at which
  auto-end does nothing (audit S7). The lower limits stop a GPS jump or a red light from ending walks (audit S5).
- **Combination checks** (`GameRulesValidator.CheckCombinations`): `VehicleSpeedMetersPerSecond` above
  `AntiCheat:MaxSpeedMetersPerSecond` and above `AntiCheat:MaxAverageSpeedMetersPerSecond` (same unit, no
  conversion); `StillRadiusMeters` at least 1.5× `Gps:AccuracyThresholdMeters` — at shipped values exactly 1.5×, so
  the accuracy threshold and the still radius are now tuned together; `StillMaxWalkedMeters` above
  `StillRadiusMeters`.
- This makes the anti-cheat speeds' own cap (15 m/s) unreachable while the vehicle speed is 9.72: the FR1 test
  `Value_at_its_upper_limit_is_allowed` with `MaxAverageSpeedMetersPerSecond, "15"` (`GameRulesTests.cs:125`) is
  changed to raise the vehicle speed with it. The two settings are now tuned together (audit S8, S9).
- **FR1 record lines that become false and are updated in PR 3/7** (`myloop-closing-an-fr`, keeping records true):
  "What shapes the app → Settings" (`AntiCheat` (8), no `AutoEnd`); "API" (the 5 phone fields); "Left to later FRs →
  FR9" (the fingerprint covers "the 4 phone settings + version" — it now covers every `ClientRules` field, audit
  S18); "How to change a rule" (every setting "above 0 … at most 5×" — `AutoEnd` has lower limits, its own upper
  limits and the two combination checks). PR 4/7 updates the record's "Saved copy" row (O10).
- A test fails when any `GameRules` number setting has no value check, so a later setting can't skip one
  (audit S4).

### API

`GET /api/rules` keeps its path, sign-in, ETag and 304. `ClientRules` gains four fields (five with O3). No other
endpoint, no database change, no migration, no SignalR change.

### Server ↔ phone contract

| C# `ClientRules` | JSON | Dart `GameRules` | Type |
|---|---|---|---|
| `AutoEndVehicleSpeedMetersPerSecond` | `autoEndVehicleSpeedMetersPerSecond` | `autoEndVehicleSpeedMetersPerSecond` | double |
| `AutoEndVehicleSeconds` | `autoEndVehicleSeconds` | `autoEndVehicleSeconds` | int |
| `AutoEndStillRadiusMeters` | `autoEndStillRadiusMeters` | `autoEndStillRadiusMeters` | double |
| `AutoEndStillSeconds` | `autoEndStillSeconds` | `autoEndStillSeconds` | int |
| `AutoEndStillMaxWalkedMeters` | `autoEndStillMaxWalkedMeters` | `autoEndStillMaxWalkedMeters` | double (O3) |

- The five FR1 fields stay. The shared sample `tests/contracts/client_rules.json` gains the new ones, each with a value
  no other field has, and the whole sample passes the startup checks (audit S19).
- The phone test "the app never knows anti-cheat numbers" allows exactly `autoEndVehicleSpeedMetersPerSecond` and
  still fails on any other key with "speed" (audit S15).
- The test that the built-in copy matches `appsettings.json` compares every field by name, so a new field can't be
  missed (audit S20).
- **Deploy order:** server first. An old phone ignores the new fields (tested in FR1). A new phone with an old server
  rejects every reply and keeps its rules (audit S22) — written in the PR and `docs/status.md`.

## Riverpod state impact

| Provider | New or changed | Holds | Reset when |
|---|---|---|---|
| `gameRulesProvider` | changed | the rules, now with the auto-end fields | never (FR1) |
| `journeyControllerProvider` | changed | walk state; one owner for start and end; the auto-end detector; the account's queue | sign-out (as today) |
| `walkDiaryStoreProvider` | new | the signed-in account's diary store (one writer) | account change (a new store for the new account; the old file stays) |
| `lastWalkEndProvider` | new | the last walk's end reason and time, until dismissed | dismissed, or sign-out |
| `walkEndNotifierProvider` | new | `WalkEndNotifier` (real or fake) | never |

**Values in a saved copy** (audit S6): the phone checks only that each auto-end field is a finite number above a
hard sanity floor (speed above 0, times at least 60 s, distances above 0); a copy that fails is rejected like a
wrongly typed one, so a corrupt "0 seconds" can't end every walk at once. The real limits stay the server's alone:
a test fails if any phone floor is tighter than the server's lower limit, so widening a server limit later never
locks installed phones on old rules.

**Saved rules after the app update** (audit S21, O10): an old saved copy without the auto-end fields is no longer thrown
away. `RulesStore.load` keeps its server values and tag and fills only the new auto-end fields from the built-in copy;
the next refresh brings the server's values (its tag differs, so it's a full reply). This keeps the FR1 decision
"after an app update the phone keeps the last rules the server sent".

## State consistency (every reader × every app moment)

State: the **walk diary** (kept across launches) and the **auto-end numbers pinned for the walk**. Readers:
**R1** the closed-app check at launch and login · **R2** the debug viewer · **R3** `endWalk` (writes) · **R4** the
auto-end detector (pinned numbers) · **R5** FR3's sender (later; FR2 only keeps the file for it).

Every row gets its test in the PR that builds its reader, through the real trigger, proven red when the behaviour is
removed (`state-lifecycle-consistency`).

| Moment | Expected | Test — red when … |
|---|---|---|
| Cold start, diary not read yet | Start waits until the diary is read; a closed walk is found (R1) | start right after launch — red when start doesn't wait for the read |
| First launch, no diary, offline | No open walk; start works as today (R1) | no file — red when a missing file throws |
| Killed mid-write | The half line is skipped; the next line starts on a new line (R1, R2, R3) | file cut mid-line — red when the next write joins it |
| Killed mid-walk, relaunched | `ended appClosed` at the last `alive` fix time; "ended early" shown once (R1) | relaunch with an open walk — red when no end line is written or the time is the launch time |
| Killed mid-walk, permission now off | Reason `locationRemoved` (R1) | relaunch, permission denied — red when the reason is `appClosed` |
| Background, screen off | Auto-end still fires on the next fix or deadline; `endAt` from fix times (R4) | fake clock and fixes with the app "paused" — red when the check needs the screen |
| Back to the app | Access checked; removed → walk ends (R3) | resume with access off — red without the resume check |
| App updated (diary format) | Lines with a known `v` load; a newer `v` is skipped (R1, R2) | v1 file read by the new reader — red when an old line is skipped |
| App updated (saved rules without auto-end fields) | Server values and tag kept; new fields from the built-in copy (R4) | old saved copy — red when the copy is thrown away |
| Corrupt line | Skipped, `diaryDamaged` shown in the viewer, no crash (R1, R2) | garbage line — red when reading throws |
| Two writers at once | One lock; no line lost (R3) | Stop and auto-end at the same moment — red when a line is missing or the walk ends twice |
| Disk full | Walk carries on; line written before the next one (R3) | write that throws, then works — red when the walk ends or the line is lost |
| Sign-out mid-walk | `ended signedOut`, loop claim sent when online, diary kept (R3) | sign-out while walking — red when the diary is cleared or no end line |
| Login as another account | Only that account's diary is read (R1) | two accounts on one phone — red when the other's open walk is found |
| Account deleted | Diary deleted after the server confirms; kept when it fails (R3) | failed delete — red when the diary or queue is cleared |
| Server rules change mid-walk | Pinned auto-end numbers stay for the walk (R4) | refresh mid-walk — red when the detector reads the live rules |
| Offline | Diary works; start blocked with today's message until FR3 (R1, R3) | offline start — red when no `startFailed offline` line |
| Back online / reconnect, or a rules refresh fails (401, 5xx) | Accepted: FR1's tests cover the rules; the pinned auto-end numbers never change mid-walk (R4) | — |
| Two closed-app checks at once (launch and login on a cold start) | One `ended` line (R1) | both triggers together — red when the walk gets two end lines |

## Risks

| Risk | Status |
|---|---|
| Land inside loops closed before a closed app ended the walk is lost | Owner decision O1 (recommended: accepted until FR6) |
| Points sent during the stretch auto-end cuts off stay on the server | Owner decision O2 (recommended: accepted) |
| A bus or city car under 35 km/h never trips the vehicle rule; its points are rejected meanwhile | Accepted by the owner in Gate 1 (35 km/h, CHEAT-6); the still and no-GPS rules end it if it stops |
| iOS may suspend the app when no fix arrives, so the still rule fires late | Mitigated: the check re-runs on the next fix, resume and launch, and `endAt` comes from fix times; only the notification is late. UNVERIFIED on a real phone — tested before merge |
| Android stops the app when permission is revoked | Mitigated: the closed-app check reads the permission and gives the right reason |
| Unsent points cleared at sign-out | Owner decision O9 (recommended: keep the file) |
| The map polls hexes every 30 s during a walk, also in the background (audit W31) | Accepted until FR8, which rebuilds the live map; FR2 adds no polling |
| A partial wake lock is held for the whole walk (audit P28) | Accepted: our own `enableWakeLock: true` (`location_service.dart:71`), kept on purpose for background tracking; FR2 doesn't change it |
| Android 13+ hides the tracking notification when notifications are refused (audit P12) | Accepted: tracking still works; UNVERIFIED |
| A tuned anti-cheat limit can come within a hair of 35 km/h | Accepted: the owner chose "above" with no margin; the startup check stops anything at or past it |
| `flutter_local_notifications` clashes with firebase_messaging on iOS | Checked on a real iPhone before the notifications PR merges |
| Mock walks can't test permission loss, vehicle speed or no fixes | Tests fake GPS at the plugin's platform layer instead (LEG-3); the mock gets no FR2 features |

## Pull requests

| PR | What | Branch |
|---|---|---|
| 1/7 | Spec: Gate 1 decisions | `claude/great-pasteur-b4y728` |
| 2/7 | This design doc and the early blind audit report, stacked on 1/7 — about 600 lines, so it carries a `Size exception:` line the owner agrees to (a design doc and its audit can't be split usefully) | a second branch, with the owner's agreement (this session can push only to the first) |
| 3/7 | Server: `AutoEnd` settings and checks, `ClientRules`, contract sample, FR1 test and record lines | `v0.1/fr2-server-settings` |
| 4/7 | Phone: rules model with the new fields, value checks and saved-copy upgrade (O10); walk diary store and debug viewer | `v0.1/fr2-diary` |
| 5/7 | Phone: one-owner start and `endWalk`, Stop dialog, closed-app check | `v0.1/fr2-walk-end` |
| 6/7 | Phone: auto-end detector and notifications | `v0.1/fr2-auto-end` |
| 7/7 | Phone: permissions; sign-out and account deletion (O4, O9); Info.plist, privacy manifest, compliance docs (O8) | `v0.1/fr2-permissions` |

Each stays near 15 files / 400 lines; any that can't says so with a `Size exception:` line.

## Early blind audit

Report: `docs/versions/1/0.1/audits/2026-10-14-fr2-early-blind-audit.md` — three agents, 91 findings, run on
`8793a00` before this doc was written. Each finding is answered above (design, owner decision or risk) or in the
`## Scenarios` table; the new cases became rows there.

## Scenarios

Every ID in `docs/scenarios.md`, answered for FR2. `open #236` means FR2 builds and tests it; the test name is
filled in by the PR that adds it.

| ID | Status | Evidence |
|---|---|---|
| LIFE-1 | open | #236: start waits until the diary is read, so a closed walk is found first |
| LIFE-2 | open | #236: no diary file means no open walk; start works as today |
| LIFE-3 | open | #236: a half-written diary line is skipped and the next write starts on a new line (audit W24) |
| LIFE-4 | open | #236: a closed app ends the walk at the last `alive` fix time (#45); the land inside its loops is owner decision O1 (FR6) |
| LIFE-5 | open | #236: auto-end runs on fixes and a one-shot deadline in the background; a late check still ends at the fix time |
| LIFE-6 | open | #236: back to the app re-checks location access; removed, GPS off or precise off ends the walk |
| LIFE-7 | open | #236: diary lines carry `v`; an old saved rules copy keeps its server values and gets the new auto-end fields from the built-in copy (audit S21) |
| LIFE-8 | open | #236: a bad diary line is skipped and shown as damaged in the debug viewer; a saved rules copy with out-of-range auto-end values is rejected (audit S6); no crash |
| LIFE-9 | open | #236: one diary writer per account; one start or end at a time; one step-claim queue per account (audit W5, W22, W23) |
| LIFE-10 | open | #236: no walk length limit; every walk timer is cancelled in `endWalk` |
| LIFE-11 | open | #236: a start that fails at any step returns to "not walking" with a `startFailed` diary line (audit W2–W4) |
| NET-1 | open | #236: the diary works offline; starting offline stays blocked with today's message until FR3, and leaves a `startFailed offline` line |
| NET-2 | n/a | FR2 adds no request; the auto-end fields come with FR1's rules request, whose failures keep the current rules |
| NET-3 | n/a | FR2 adds no request; walk start keeps FR1's 3 s wait and the request's 30 s limit |
| NET-4 | n/a | FR2 adds no request; FR1 covers an unreadable rules reply |
| NET-5 | open | FR3: sending diaries and a killed walk's points when back online |
| NET-6 | n/a | FR2 adds no server write; the loop claim it sends from `endWalk` is today's request |
| NET-7 | n/a | FR2 adds no request; a forced sign-out writes only a diary line |
| NET-8 | n/a | FR2 adds no request |
| NET-9 | n/a | FR2 adds no request |
| NET-10 | open | FR3: a 4xx still deletes a batch's points (audit W34); the phone never deletes a diary because of a reply |
| NET-11 | open | #236: each `WalkEndReason` has its own message; none says "anti-cheat" |
| AUTH-1 | open | #236: sign-out ends the walk (`signedOut`, online and offline), sends its loop claim when online, keeps the diary and, with O9, the account's queue file |
| AUTH-2 | open | #236: login reads only that account's diary file |
| AUTH-3 | open | #236: diary files are named by user id; a new account starts with none; a deleted account's diary is deleted (O4) |
| AUTH-4 | open | FR12: guests don't exist yet |
| AUTH-5 | open | #236: a forced sign-out writes `signedOutForced` and then tears down as today |
| AUTH-6 | n/a | FR2 doesn't touch sign-in |
| PRIV-1 | n/a | no new endpoint |
| PRIV-2 | n/a | no hub change |
| PRIV-3 | open | #236: diary lines hold no coordinates and FR2 code logs none; a test reads every event type for latitude/longitude fields |
| PRIV-4 | open | #236: the phone diary is deleted when the server confirms the account deletion; the server copy is FR12's |
| PRIV-5 | open | #236: the walk is stopped (GPS and drain) before the delete request; the diary writer's lock is held while the file is deleted |
| PRIV-6 | n/a | nothing about other players |
| PRIV-7 | n/a | the diary only holds the user's own events |
| DEV-1 | open | #236: `checkAccess()` never opens Settings; the screen explains and offers an "Open settings" button; restricted gets its own message (audit W6, P7–P9) |
| DEV-2 | open | #236: stream error, stream end and resume run `checkAccess()`; location removed or GPS off ends the walk; Android's stop-on-revoke is caught by the closed-app check (audit P1–P4, P2) |
| DEV-3 | open | #236: precise location turned off mid-walk ends the walk (O6); asking for precise location before a walk is FR3's |
| DEV-4 | open | #236: notifications asked at the first walk start if never asked (O5); refusing never blocks; messages then show in the app only |
| DEV-5 | open | #236: a failed diary write keeps the line in memory and retries; the walk carries on; shown in the debug viewer |
| DEV-6 | open | #236: auto-end uses GPS fix times and a monotonic clock; diary times are UTC; the queue's phone-clock `capturedAt` stays FR3's (audit W21) |
| DEV-7 | open | #236: an OS kill is "app closed" (#45); a late auto-end check still ends at the fix time; the up-front warning is FR4's |
| DEV-8 | open | #236: auto-end adds one one-shot timer, no periodic one; the `alive` diary line is at most once a minute |
| DEV-9 | open | #236: auto-end uses only fixes that pass the accuracy threshold; the first-fix filter is FR3's |
| DEV-10 | open | #236: vehicle needs the recorded path's average speed over 3 minutes, so one jump or burst can't trigger it and a jittering still phone can't either; `pos.speed` is never used |
| IN-1 | open | #236: every `AutoEnd` setting (four, five with O3) is rejected at startup when NaN or Infinity |
| IN-2 | open | #236: each `AutoEnd` setting has a lower limit (speed above 0, 60 s, 300 s, 1.5× accuracy, 100 m walked) |
| IN-3 | open | #236: each `AutoEnd` setting has an upper limit chosen so auto-end still does something (60 km/h, 600 s, 300 m, 3600 s, 2000 m) |
| IN-4 | open | #236: a missing `AutoEnd` setting stops the server; the phone rejects a reply missing one of the auto-end fields |
| IN-5 | open | #236: an old phone ignores the new fields (FR1 test); deploy order server first |
| IN-6 | open | #236: each `AutoEnd` setting gets a test at its shipped value and its neighbours |
| IN-7 | open | #236: startup checks: vehicle speed above both anti-cheat speeds; still radius at least 1.5× the accuracy threshold (O3); still walked distance above the still radius |
| IN-8 | open | #236: the `AutoEnd` checks run at startup with FR1's checks |
| SRV-1 | open | #236: the walk pins its auto-end numbers with its rules; the diary records the rules version and tag |
| SRV-2 | open | #236: server deployed first; written in the PR and status page |
| SRV-3 | n/a | no server write |
| SRV-4 | n/a | searched: `api/` for startup code and migrations FR2 adds — none; FR2 has no schema change; the existing startup rewrite is FR7's |
| SRV-5 | n/a | searched: `api/` and `appsettings*.json` for seed data FR2 adds — none; seeded bots are FR13's |
| SRV-6 | n/a | no new endpoint; a diary grows by about one line a minute of walking |
| SRV-7 | n/a | no new endpoint |
| SRV-8 | open | #236: when auto-end moves the end time back, the phone works out time and distance again from the kept points and their GPS times (O2) |
| DATA-1 | open | #236: new register row for `walk_diary_store.dart` (deleted on account deletion, FR2; after the server confirms, FR3); `user_session_teardown.dart` and `journey_controller.dart` rows change with O4 and O9 |
| DATA-2 | n/a | searched: the FR2 section of `requirements.md` for promises without a number — none; "deleted only after the server confirms" is part of #44 |
| GAME-1 | n/a | FR2 doesn't change how loops capture (FR6) |
| GAME-2 | n/a | FR2 doesn't change how loops capture (FR6) |
| GAME-3 | n/a | FR2 doesn't change how loops capture (FR6) |
| GAME-4 | open | #236: jitter adds no distance (today's noise floor) and doesn't restart the still count inside the radius |
| GAME-5 | n/a | FR2 doesn't change loop limits (FR6) |
| GAME-6 | n/a | FR2 doesn't change crossing detection (FR6) |
| GAME-7 | open | #236: no accepted fix for 30 minutes ends the walk as `noGps`; shorter gaps are FR4's |
| GAME-8 | n/a | FR2 doesn't change sending (FR3) |
| GAME-9 | open | #236: equal or backwards fix times are skipped by the auto-end checks |
| GAME-10 | open | #236: auto-end never deletes points; the server still judges them |
| GAME-11 | open | #236: Stop warns from the phone's own loop check when the last stretch isn't closed; that stretch is never captured |
| GAME-12 | n/a | FR2 doesn't change exploration (FR7) |
| GAME-13 | n/a | FR2 doesn't change the preview (FR8) |
| GAME-14 | open | #236: every end goes through `endWalk`, which sends the loop claim when the phone or the preview found a loop, then drains once; saving and retrying the claim offline is FR3's |
| GAME-15 | open | #236: no Pause (#32 dropped); vehicle, still and no-GPS auto-end, end time moved back, user told |
| GAME-16 | n/a | FR2 doesn't change exploration (FR7) |
| CHEAT-1 | n/a | FR2 doesn't change what the server judges (FR6) |
| CHEAT-2 | n/a | FR2 doesn't change timestamps sent to the server (FR3, FR5) |
| CHEAT-3 | n/a | FR2 doesn't change the server's step checks (FR5) |
| CHEAT-4 | accepted | owner, Gate 1: driving under the server limit is FR5's; a bus under 35 km/h doesn't auto-end |
| CHEAT-5 | n/a | FR2 doesn't change replay detection (FR5, FR6) |
| CHEAT-6 | open | #236: the only speed the phone gets is the 35 km/h auto-end speed, kept above both server limits at startup; the "no anti-cheat numbers" test allows exactly that field |
| LEG-1 | open | #236: searched: `journey_controller.dart`, `journey_screen.dart`, `location_service.dart`, `user_session_teardown.dart` — no confirm on Stop, end flow in the screen, jump to Settings, "Always" log, stream errors ignored; each fixed in FR2. Offline start block: FR3 |
| LEG-2 | open | #236: the "Always" log, the unused "Always" purpose string and the dead `pos.speed >= 0` check are removed |
| LEG-3 | open | #236: GPS faked at the plugin's platform layer and time with a fake clock; the mock walk is not used to test FR2 |
| LEG-4 | open | #236: FR2 tests in `mobile/test/v0_1/fr2/` and `tests/MyLoop.V01.Tests`, run by CI |
| LEG-5 | open | #236: searched: every caller of `stopJourney` and `abandonForSignOut` (journey screen, session teardown) — all go through `endWalk`; the auto-end numbers are read only from the pinned rules |
| LEG-6 | open | #236: `/dev/walk-diary` and its button exist only `if (kDebugMode)` |
| LEG-7 | open | #236: `docs/learnings/phase-1.md`'s privacy-manifest lesson is picked up by O8; no other lesson is about walks |
| LEG-8 | open | #236: auto-end tests use a fake clock and check the exact limits (3:00 and 30:00, one millisecond either side) |
| LEG-9 | n/a | no CI change beyond adding tests |
| LEG-10 | open | #236: the diary and auto-end are their own classes; `journey_controller.dart` only wires them |
| LEG-11 | n/a | no secrets |
| LEG-12 | open | #236: no "Pause" text in the app outside the debug mock walk (searched `mobile/lib`) |
| API-1 | open | #236: the auto-end fields, each with the unit in the name, double/int as in the contract table, tested against `tests/contracts/client_rules.json` |
| API-2 | open | #236: the server is the one source; the built-in copy is compared with `appsettings.json` field by field |
| API-3 | open | #236: `RulesHttpTests` checks the auto-end fields over real HTTP |
| STORE-1 | open | #236: `app-store-compliance` on the notifications and permissions PRs; privacy manifest and purpose strings (O8) |
