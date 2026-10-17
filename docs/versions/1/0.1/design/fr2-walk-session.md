# FR2 — Walk session: design

Task: #236. Requirement: `docs/versions/1/0.1/requirements.md` → FR2. Gate 1 answers for every scenario ID: the
comment "Gate 1 — scenario answers" on #236. Early blind audit: `audits/2026-10-14-fr2-early-blind-audit.md`.

**Status:** approved (Gate 2): merged in #237 on 2026-10-17. The owner answered the decisions O1–O10 on 2026-10-15
and O11 on 2026-10-17; the spec and #236 carry them. PR 2/7 fixed the gaps a re-check and its review found the
same day (audit findings answered only halfway, and new ones).

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
3. **Forgotten walks end on their own, with a warning.** If you ride in a vehicle (faster than 35 km/h for 3
   minutes), the app says "Looks like you're in a vehicle. This walk ends in 10 s" and ends the walk, with the
   vehicle part taken out. If you stay still for 10 minutes, the app warns you at 5 minutes, counts down the last
   minute, and ends the walk where you stopped. There's no cancel and no Pause.
4. **Accidents end the walk where it stopped.** If the app is closed (the phone kills it, it crashes, the phone
   restarts), location is removed, GPS or precise location is turned off, or you sign out, the walk ends at its last
   point. Every loop you completed is already captured, because each loop is sent the moment it closes; only the
   open stretch since the last loop can be lost.
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
| Forgetting to stop and getting in a car | The walk runs on, sending rejected points | After 3 minutes above 35 km/h: a 10-second warning, then the walk ends without the car part |
| Standing still or leaving the phone on a table | The walk runs for hours | Warning at 5 minutes, countdown in the 10th minute, then the walk ends where you stopped |
| Phone kills the app mid-walk | The walk is gone without a word, and so is the land of every loop | Next launch: "Your walk ended early at 10:42"; every completed loop is already captured |
| Turning off location or GPS mid-walk | "Recording" carries on with nothing recorded | The walk ends and is saved, and the app says why |
| Signing out mid-walk | The walk is thrown away | The walk ends and is saved; its closed loops are sent first when online (O9) |
| A walk that went wrong | No way to find out why | The diary shows every event; the owner can read it in a debug build now, and on the server after FR3 |

Things a user will **not** get: no Pause button, and a closed app never resumes the walk.

## Owner decisions from the early blind audit (answered 2026-10-15; O11 on 2026-10-17)

| # | Question | Owner's answer |
|---|---|---|
| O1 | Today a loop's land is sent only at Stop, from a path in memory, so a closed app loses every completed loop | **Keep completed loops.** Each loop is sent the moment the phone sees it close (after the 3-minute vehicle check); only the open stretch since the last loop can be lost. A loop that couldn't be sent is tried again at the end of the walk; keeping it across an app close is FR3's |
| O2 | What happens to a walk that turns into a vehicle ride | **A vehicle is never part of a walk.** "Looks like you're in a vehicle. This walk ends in 10 s", a countdown, no cancel; then the walk ends with the vehicle stretch taken out. The owner first asked to delete the whole walk; that was dropped because it would delete honestly walked land (#35, #43), false alarms (a train, a GPS glitch) would wipe real walks, and the server already rejects every driving point |
| O3 | How long "still" lasts, and how to tell still from jitter and from laps | **10 minutes**, warning at 5 minutes, a 60-second countdown in the last minute, no cancel. Still = within 75 m of the average of the fixes and under 250 m of recorded path, so jitter doesn't reset it and laps don't count as still. The 250 m is checked on a real indoor trace before PR 3/7 merges (400 m if jitter adds more; a slow lap at 3 km/h adds 500 m in 10 minutes). The startup check is "still radius at least 1.5× the accuracy threshold" |
| O4 | A failed account deletion wipes the walk | **Fix in FR2:** points and diary are cleared only after the server confirms the deletion |
| O5 | Notifications are already asked at login | **Ask at the first walk start only if never asked** |
| O6 | Precise location turned off mid-walk | **Ends the walk at once**, saved, with that reason |
| O7 | GPS switched off mid-walk, even briefly | **Ends the walk at once** |
| O8 | Privacy manifest, purpose strings, location pre-prompt | **In FR2's permissions PR**: `PrivacyInfo.xcprivacy`; the "While using" string says tracking goes on with the screen off; a short screen before the first location prompt; `docs/compliance/` updated. The unused "Always" string is removed only if geolocator's iOS code doesn't reference the "Always" API (checked first; otherwise kept with honest wording) |
| O9 | Sign-out deletes the walk's unsent points | **Keep them** in the account's own queue file; they go with that account's next walk (at sign-in from FR3). `ended signedOut` is written online and offline. The register row for `journey_controller.dart` changes |
| O10 | The saved rules copy after the app update has none of the new fields | **Keep its server values, drop its tag**, fill only the new fields from the built-in copy, so the next refresh is a full reply; the diary records the auto-end values the walk used |
| O11 | The Stop warning needs to know whether the current loop is really closed, but the phone doesn't know the server's minimum loop size (FR1 kept it server-only because the phone didn't use it) | **Send it to the phone** (2026-10-17): `Loop:MinAreaSquareMeters` becomes a phone field. It is a loop rule, not a cheat number. The phone's loop check then drops loops the server would reject, so the warning is reliable and no too-small loop is sent |

## Decisions already approved (Gate 1)

The spec's FR2 section has them in full: no Pause (#32 dropped); diary #44; closed app ends the walk #45; sign-out
ends and saves the walk #46; auto-end at 35 km/h for 3 min or still for 10 min (O2, O3), settings, end time moved back,
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
     each recorded path point's GPS time next to the path, and the walk's start time is the first fix's GPS time, so
     start and end come from the same clock (audit W21, P25);
  4. sends any loop still waiting for the vehicle check if no vehicle stretch covers it, resends loops whose claim
     failed (see "Each loop is sent when it closes"), then sends the whole kept path once as today's end-of-walk
     claim. That last claim is a safety net: the server finds every loop in it, skips hexes already owned and folds it
     into the same Claim, so a loop the phone's own check missed or cut at the wrong point is still captured. Then it
     drains the queue once with `drainNow` (today's `drainBeforeCapture`, which has no caller, is removed — audit
     W32). All of step 4 shares one time limit, `walkEndSendLimit` (30 s, like FR1's `rulesRequestLimit`), so a send
     stuck in the sign-in token step (FR1 record, "Known limits") can't hang the end of a walk;
  5. runs today's post-walk refresh (`refreshProfileAfterWalk`, which also refreshes the rules — FR1's "after a
     walk" trigger) and reloads the map's hexes. Today it takes the screen's `WidgetRef`; it gets a `Ref`-based form
     so the controller can call it with no screen open;
  6. publishes the result in `lastWalkEndProvider` (below): reason, end time, walk time (`endAt` minus the start's
     GPS time, so a trimmed walk shows its trimmed time — SRV-8), distance (of the kept path), and what the walk
     captured (the sum of every claim's `newlyClaimedCount`). After a closed app these come from the diary: the
     `started` line's `startAt`, the last `alive` line's `distanceMeters` and the sum of the `loopSent` lines.
     Whichever screen is showing presents today's celebration with it (it shows distance and walk time,
     `celebration_dialog.dart:44-45`), so a walk ended by auto-end, a lost permission or a closed app shows its
     result too (FR8 rebuilds that screen).
- Callers: Stop (after the dialog), auto-end, location removed / GPS off / precise off, sign-out, and the closed-app
  check at launch (which only writes the diary and publishes the result — the GPS is already gone).
- `WalkEndReason`: `stoppedByUser`, `autoEndedVehicle`, `autoEndedStill`, `noGps`, `locationRemoved`, `gpsOff`,
  `preciseLocationOff`, `appClosed`, `signedOut`, `signedOutForced`, `accountDeleted`. Each has one user message;
  none says "anti-cheat" (NET-11).
- **Each loop is sent when it closes (O1).** A new `LoopDetector.findLoops(path, rules)` returns each closed loop's
  point range, keeping only loops at least `minLoopAreaSquareMeters` in area (O11), the server's own minimum (today's
  `countLoops` only counts them, over-counts out-and-back paths and only triggers the server preview — audit W11).
  It copies the server's loop finding (`ExtractLoops` and `FindClosureLoops` in `HexGridService.cs`) and its area
  filter (`GeoService.CalculatePolygonArea`), with the server's constants: `GameConstants.EarthRadiusMeters`
  (6,371,000 m, not geolocator's own distance) and `MetersPerDegreeLat` (111,320). It does not copy the server's
  duplicate removal, which needs polygon geometry the phone doesn't have: a second lap of the same block is sent and
  gains nothing, because the server skips hexes the user already owns. A shared file of test paths
  (`tests/contracts/loop_paths.json`) pins the copy: each path must give the same loops (first and last point) after
  the area filter from `findLoops` and from the server's internal `FindClosureLoops` plus `CalculatePolygonArea`
  (visible to `MyLoop.V01.Tests`). The paths include an area just over and just under 5,000 m², closure at 50 m
  ± 1 cm, a figure-8 and two laps of one block (GAME-13, API-2).
  When it finds a new loop, the controller sends that loop's path as a loop claim with the walk's `WalkSessionId`:
  - **Not while a vehicle could be involved.** A loop claim carries no times, so the server can't speed-check it.
    A loop is sent only once `VehicleSeconds` have passed after its last point with no vehicle verdict, and never if
    its own points (which carry GPS times) average above the vehicle speed; a loop inside a cut-off vehicle stretch
    is never sent. Stop sends a waiting loop at once if no vehicle stretch covers it. Cost: a loop closed in the last
    3 minutes before the app is closed is lost with the open stretch.
  - **Safe on the server.** It skips hexes the user already owns and folds every claim of one walk into one Claim
    (`TerritoryService.cs:96-118`, #56). Each loop claim carries only the loop's own points, but the end-of-walk
    whole-path claim repeats them, so the old beta's distance XP is counted twice for looped distance — accepted (risk
    table): XP is old beta code no 0.1 FR owns yet, left until an FR rebuilds or removes it, and no land is counted
    twice.
  - **Failures.** A 400 is the server's verdict on the data ("no hexes captured", the daily cap): it is final, never
    resent, and gets a diary line `loopRejected` (NET-10). Every other failure — no network, a timeout, any other 4xx
    (401, 403, 404, 408, 409, 413, 429) or a 5xx — is kept in memory and resent by `endWalk`; keeping it across an
    app close is FR3's.
  - **Until PR 6/7 merges** (the vehicle check), loops are sent only at Stop, as today, so master never sends a loop
    the vehicle check hasn't seen.
  - The Stop dialog's "loop isn't closed" warning uses the same `findLoops`.
- The short-walk notice ("Walk a bit more") stays, but the walk still gets its diary lines (audit W10).
- `startJourney` refuses while a walk is starting or running (audit W5), and a start that fails at any step goes back
  to "not walking" with the diary line "start failed: <reason>" (audit W2, W3, W4). Order: diary `startTapped` →
  permission (and the location pre-prompt) → notification ask (O5) → reachability check → first fix → FR1's `ready` +
  `refreshWithin(walkStartRulesWait)` + pin. Every dialog comes before the pin, as FR1's D1 requires, so a refresh
  during a dialog isn't missed. The walk's start time is the GPS time of the first fix (today's
  `getCurrentPosition`, which is checked against the accuracy threshold only from FR3, DEV-9), and the path starts at
  that same fix, so no path point comes before the start time or lacks a time. The walk id and the diary's "start
  tapped" line are written first, before the reachability check, permission and first fix.
- One `StepClaimQueue` per account, owned by the controller across walks, so a stopped walk's last batch can't
  overwrite the next walk's points (audit W22). The queue's other problems — a failed point save (phone full) that
  nothing catches, and a half-written line that the next point joins and spoils (audit W24,
  `journey_controller.dart:292`, `step_claim_queue.dart:90`, `:129-136`), a failed rewrite sending points twice and
  leaving a `.tmp` file (audit W25), and lines with no format version (audit W26) — are FR3's, which rebuilds sending.
- **Walk time on screen (audit W30).** The walk's start and end times are GPS times (step 3 above). The time shown
  during the walk (the journey screen and the home walk button, `home_screen.dart:533`) is never the phone clock
  minus a GPS time: it comes from a `Stopwatch` started at the first fix, and is never less than the latest fix's
  GPS time minus the start's, so a stopwatch that stops while the phone sleeps (audit P24, UNVERIFIED) catches up on
  the next fix. The controller's 1-second timer stays, because it also clears the one-shot messages
  (`journey_controller.dart:82-99`), but it reads that time instead of `DateTime.now()` (`:594`) and pauses while
  the app is in the background (DEV-8). The time a walk records and shows in its result is `endAt` minus the
  start's GPS time (step 6).
- The app version comes from the new package `package_info_plus` (audit W1).

### The walk diary (#44)

- **Code:** `mobile/lib/features/walk_session/` (the diary store, the auto-end detector, the end reasons), a
  feature folder as CLAUDE.md asks — outside `mobile/lib/shared/`, so the data-removal script doesn't see it and
  its register row is added by hand.
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
  | `event` | string | `startTapped`, `started`, `startFailed`, `alive`, `ended`, `gpsError`, `loopSent`, `loopRejected`, `endClaimRejected`, `diaryDamaged` |
  | `detail` | object | per event, below; never coordinates |

  - `started`: `startAt` (GPS time of the first fix, the walk's start time), `rulesVersion`, `rulesTag` (the FR1
    fingerprint of the phone fields; after O10's upgrade it can be empty), the auto-end values the walk pinned, so
    the line names the exact numbers whatever the tag (audit S17, W29, O10), `appVersion`, `permission`
    (`whileUsing`/`always`), `precise` (bool), `notifications` (`granted`/`denied`/`notAsked`).
  - `alive`: `lastFixAt` (GPS time of the last accepted fix), `distanceMeters` (the kept path's distance up to
    `lastFixAt`, or up to `stillSince` during a still stretch, so a closed app's result leaves the stretch out of its
    distance as well as its time — spec #34; a number with no location) and, during a still stretch, `stillSince`
    (GPS time of its first fix). Written at most once a minute while walking, so a closed app's end time is known
    within a minute (audit W19) and its result can show time and distance. A one-hour walk writes about 60 lines.
  - `ended`: `reason` (a `WalkEndReason`), `endAt` (GPS time of the walk's last fix), and for auto-end the setting
    values that ended it.
  - `loopSent`: the claim's `newlyClaimedCount`, so a closed app's result can still say what the walk captured.
    `endClaimRejected`: a 400 on the end-of-walk whole-path claim — normal for a walk with no loop, so it is kept
    apart from `loopRejected`.
  - `startFailed`: `reason` (`offline`, `permissionDenied`, `permissionDeniedForever`, `restricted`, `gpsOff`,
    `noFix`, `diskError`). A start with no signed-in account has no diary to write to: it is logged and the
    start refused (audit W3).
- **A half-written line** (app killed mid-write) is skipped on read; the next write starts with `\n` if the file
  doesn't end with one, so it never joins a broken line (audit W24).
- **Write fails** (phone full): the line stays in memory and is written before the next one; the failure is logged
  and shown in the debug viewer; the walk carries on (DEV-5).
- **Kept until:** the account is deleted (FR2), or the server confirms it has the lines (FR3). Sign-out keeps it.
- **Debug viewer:** route `/dev/walk-diary`, added only in debug builds like `/dev/mock-walk`, with a button on the
  journey screen in debug builds. The router gets the debug flag as a parameter (defaulting to `kDebugMode`), so a
  test can build it as a release build and prove the route and button are missing (`kDebugMode` is always true in
  tests). It lists walks, their events and any write failures or damaged lines.

### Closed app (#45)

- At launch (and at login), once the signed-in account is known, the diary is read. Both can fire on a cold start,
  so the check runs once at a time through the diary's lock, and a walk that already has its `ended` line is
  skipped. So is the walk this app run started (the controller's current walk id), so a check that runs late, after
  the user has tapped Start, can't end the running walk. A walk with a `startFailed` line never ran and is skipped
  too. A walk with `startTapped` or `started` and no `ended` or `startFailed` line was closed mid-walk.
- `endWalk(appClosed)` writes `ended` with `endAt` = the start of the still stretch if the last `alive` line has a
  `stillSince`, else its `lastFixAt`; with no `alive` line, the `started` line's `startAt`, or the `startTapped`
  line's `at` if the walk never started (an empty walk the diary still records — audit P27).
- Until PR 7/7 adds `checkAccess()`, the reason is always `appClosed`.
- If location permission is now off, the reason is `locationRemoved` instead, and if only approximate location is
  allowed, `preciseLocationOff`: Android stops the app when either is changed, so this is the only place those cases
  can be seen (audit P2).
- The user sees "Your walk ended early at 10:42" once, through `lastWalkEndProvider`, but only for a walk with a
  `started` line; a start the app closed before it began (P27) gets its `ended` line and no message.
- The killed walk's unsent points stay in the account's queue and go with that account's next walk, as today (FR3
  sends them at launch and sign-in). Its completed loops were already sent when they closed (O1).

### Auto-end (#34)

`AutoEndDetector` — a plain Dart class with no plugins, fed by the controller, reading the walk's pinned rules
(never the live provider — audit S23). It only uses fixes that pass the GPS accuracy threshold, with the fix's own
GPS time (`Position.timestamp`), never `pos.speed` (it reads 0 when missing — audit P19).

- **Vehicle:** over the last `VehicleSeconds`, the walk's recorded path (the points the noise floor kept, with their
  GPS times) grew faster than `VehicleSpeedMetersPerSecond` on average, and the window really spans that long. Using
  the recorded path, not every raw fix, keeps a jittering still phone from adding up fake distance (a test with a
  jittering still phone); one GPS jump can't do it alone (DEV-10). Hops with equal or backwards times are skipped
  (GAME-9). A tunnel, or the plugins sending only the newest fix of a batch (audit P15), gives one long hop, which
  still counts at its true average speed. `endAt` = the last point before the window. Then the 10-second warning
  (O2): "Looks like you're in a vehicle. This walk ends in 10 s", a countdown, no cancel; at zero, `endWalk`.
- **Still:** for the last `StillSeconds`, every accepted fix is within `StillRadiusMeters` of the average of those
  fixes and the recorded path grew by less than `StillMaxWalkedMeters` (O3); one fix outside is ignored, two in a row
  restart the count. `endAt` = the last point before the still stretch began, as the spec says. Warnings (O3): 5
  minutes before the end, "You've been still for N minutes. This walk ends in 5 minutes", where N comes from
  `StillSeconds` (5 at the shipped 600); in the last 60 seconds, a countdown. Real movement at any point restarts the
  count and clears the warning. With the app in the background each warning is a notification (in the app only if
  notifications are refused). The warning times (5 minutes before, the last 60 s, the vehicle's 10 s) are fixed UI
  timings in the phone, not game rules; a warning that would fall before the stretch starts (`StillSeconds` of 5
  minutes or less) is skipped.
- **No fixes at all vs no GPS.** Tracking uses a 5 m distance filter, so a phone lying still gets no fixes at all;
  silence with no stream error counts as **still** (`autoEndedStill`). The same silence comes from a tunnel, an
  underground train or a silent Android stream (audit P6), so these warnings use words that fit both: "We haven't
  seen you move for 5 minutes. This walk ends in 5 minutes". **No GPS** is when fixes keep arriving but
  none passes the accuracy threshold for `StillSeconds` (10 minutes) → `noGps`, with its own text ("No GPS for 5
  minutes. This walk ends in 5 minutes"), so a dead
  GPS or a lost precise location isn't reported as "you stopped moving" (audit
  P23). A start whose first fix never comes fails as `startFailed noFix` (today's 15 s limit).
- **Clock:** the counts use a monotonic `Stopwatch` while the app runs, and one one-shot `Timer` set to the next
  deadline. Auto-end's only periodic timer is a 1-second ticker for a countdown on screen; it runs only during a
  countdown and is cancelled by `endWalk` or by movement (DEV-8). After the phone suspends the app (possible on iOS
  when no fix arrives — audit P14, UNVERIFIED), the check runs again on the next fix, on resume and at launch;
  because `endAt` comes from fix times, a late check still ends the walk at the right time; the warnings were
  scheduled ahead as notifications. Whether a `Stopwatch` keeps counting while the phone sleeps is UNVERIFIED too
  (audit P24); it is checked on a real iPhone before PR 6/7 merges.
- **Warnings while the app is suspended.** Each warning and the "walk saved" message are also scheduled ahead of time
  as local notifications (`flutter_local_notifications` scheduled delivery), moved back whenever the user moves, and
  cancelled when the walk ends. So a suspended iPhone still shows them on time (audit P14), the same approach FR4's
  iOS alarm uses.
- **Ending:** `endWalk(autoEndedVehicle | autoEndedStill | noGps, endAt: …)`, then the "walk saved" message. Points
  recorded during a warning or countdown come after `endAt`, so they are trimmed off with the stretch.

### Permissions (#42)

`LocationService` changes; `ILocationSource`-style interface kept so tests swap it.

- `checkAccess()` returns one of: `granted`, `approximateOnly`, `denied`, `deniedForever`, `restricted`, `gpsOff`.
  It never opens Settings (audit W6). The screen shows a plain message and, for `deniedForever` and `gpsOff`, an
  "Open settings" button the user taps; `restricted` says location is blocked on this phone (audit P8).
- Opening the walk map only reads the current access and the last known position; it asks for permission only when
  the user taps "Start walk".
- **The first location prompt (audit P7).** Today a new user meets the system location prompt during sign-up, on
  the set-home screen (`set_home_screen.dart:40-43`), with no explanation, and on iPhone a first "Don't allow" can't
  be asked again. Set-home stops asking: it only reads the current permission and, when location isn't allowed
  yet or no position comes back (GPS off, the catch at `set_home_screen.dart:60-64`), skips itself by running
  `_finishOnboarding` at once, which is what its "Skip for now" does today
  (`set_home_screen.dart:103-106`, `:216-219`; that button only shows once a position is found, and the
  no-permission state has only a Retry that could never work). FR13 removes the screen with home location (#23).
  So the first system prompt is always the one at "Start walk", after the explain screen (O8), and the explain
  screen's text ("MyLoop uses your location only while you walk") stays true. Cost until FR6: a user with no home
  gets the 7-day decay for all land (`TerritoryService.cs:1182-1186`), so land walked more than 30 km from where
  they signed up decays in 7 days instead of 15–90 (`GameConstants.cs:49-70`) — see the risk table.
- During a walk:
  - **stream error:** a "location services disabled" error (Android's error when GPS is turned off — audit P1) ends
    the walk at once with `endWalk(gpsOff)`, even if GPS is already back on (O7: even briefly). Any other error runs
    `checkAccess()`. Location off → `endWalk(locationRemoved)`; GPS off → `endWalk(gpsOff)` (O7); precise off →
    `endWalk(preciseLocationOff)` (O6); still granted → diary `gpsError` and carry on (iOS sends one generic error
    for all of these — audit P3);
  - **first inaccurate fix:** the first fix that fails the accuracy threshold after an accepted one also runs
    `checkAccess()` once (again only after another accepted fix). So precise location turned off while the app is
    in the background ends the walk at once as `preciseLocationOff`, not 10 minutes later as `noGps` (O6). Whether
    iOS sends a stream error in that case is UNVERIFIED, so this doesn't rely on one;
  - **before the first still or no-GPS warning:** `checkAccess()` runs once more, because after precise location is
    turned off, coarse fixes may stop arriving altogether under the 5 m distance filter (UNVERIFIED), and the walk
    must then end as `preciseLocationOff`, not as still (O6, audit P23). Checked on a real iPhone before PR 7/7
    merges;
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
- At walk start, if notification permission was never asked, ask it (O5). Refusing never blocks the walk. "Never
  asked": on iOS the system says so (`notDetermined`); Android 13+ can't tell, so the app keeps its own "asked" flag
  on the phone and also counts today's login ask.
- Android 13+ hides the tracking notification when notifications are refused (audit P12, UNVERIFIED); tracking
  still works and the status bar shows location in use. Accepted.
- Shown only when the app is in the background; in the app, `lastWalkEndProvider` shows the message on the home and
  journey screens until the user dismisses it (audit P17).

### Sign-out and account deletion (#46)

- **Sign-out:** `abandonForSignOut` first calls `endWalk(signedOut)` when a walk is running — online and offline.
  Online it also sends waiting loops and drains once, within a short limit (5 s) so a stuck send never holds sign-out
  open. Then it tears down as today, except that the account's step-claim queue file is kept (O9); the diary file is
  kept. Failed loop claims still in memory are lost until FR3 keeps them.
- **Forced sign-out:** `endWalk(signedOutForced)` stops GPS and writes the diary line but sends nothing (there is no
  token); the teardown follows and, as at sign-out, keeps the account's queue file and diary (O9).
- **Account deletion:** `endWalk(accountDeleted)` stops the walk (GPS and drain) first, as today; only after the
  server confirms the deletion, the queue is cleared and the diary file deleted (O4). A failed deletion keeps both;
  the diary's `ended accountDeleted` line then names a deletion that failed, the user sees "Your walk was saved.
  Your account wasn't deleted — try again.", and the next launch finds the walk already ended.
- A signed-out account's diary waits on the phone until that account signs in again and FR3 sends it; a diary is
  small (about one line a minute of walking). Files of accounts that never return: FR3 decides (audit W28).

### Stop dialog (#33)

- "End walk?" with "End" and "Keep walking".
- The warning comes from the phone's own loop check (`findLoops`, with the server's minimum loop area — O11), so it
  works offline: the controller keeps the path index where the phone last found a loop; if points were walked after
  it, the dialog adds "Your current loop isn't closed. Land inside it won't be captured." (audit W35). Walking up a
  street and back is no loop, so it gets the warning. The server stays the judge, and the end-of-walk claim (step 4
  of `endWalk`) still sends the whole path.

## How it works — server

### Settings

New section `AutoEnd` in `GameRules` (its own section, never inside `AntiCheat` — audit S16). Plain numbers with the
unit in the name, never `TimeSpan` (audit S2). `VehicleSeconds` and `StillSeconds` are `int` in `GameRules` (so
"180.5" stops startup, as `MinPoints` does today); the speed and distances are `double`. The `_comment` in
`appsettings.json` gains "and AutoEnd" among the groups sent to the phone:

| Setting | Shipped | Allowed | Sent to phone |
|---|---|---|---|
| `AutoEnd:VehicleSpeedMetersPerSecond` | 9.73 (35.0 km/h; 9.72 is 34.99) | above 0, at most 16.67 (60 km/h); above both anti-cheat speeds | yes |
| `AutoEnd:VehicleSeconds` | 180 | 60 to 600 | yes |
| `AutoEnd:StillRadiusMeters` | 75 | at most 300; at least 1.5× `Gps:AccuracyThresholdMeters` | yes |
| `AutoEnd:StillMaxWalkedMeters` | 250 (400 if the indoor trace needs it) | 100 to 1000; above `StillRadiusMeters` | yes |
| `AutoEnd:StillSeconds` | 600 (10 min) | 300 to 1800 | yes |

- `Loop:MinAreaSquareMeters` (5000, FR1's setting and limits, unchanged) is now also sent to the phone (O11).
- `Version` goes from 1 to 2 (audit S17).
- The upper limits are tighter than FR1's "5× shipped" on purpose: 5× would allow 175 km/h or 150 minutes, at which
  auto-end does nothing (audit S7). The lower limits stop a GPS jump or a red light from ending walks (audit S5).
- **Combination checks** (`GameRulesValidator.CheckCombinations`): `VehicleSpeedMetersPerSecond` above
  `AntiCheat:MaxSpeedMetersPerSecond` and above `AntiCheat:MaxAverageSpeedMetersPerSecond` (same unit, no
  conversion); `StillRadiusMeters` at least 1.5× `Gps:AccuracyThresholdMeters` — at shipped values exactly 1.5×, so
  the accuracy threshold and the still radius are now tuned together; `StillMaxWalkedMeters` above
  `StillRadiusMeters`. So a test that puts the still radius at its upper limit (300) also raises
  `StillMaxWalkedMeters` above 300, since it ships at 250.
- This makes the anti-cheat speeds' own cap (15 m/s) unreachable while the vehicle speed is 9.73: the FR1 test
  `Value_at_its_upper_limit_is_allowed` with `MaxAverageSpeedMetersPerSecond, "15"` (`GameRulesTests.cs:125`) is
  changed to raise the vehicle speed with it. The two settings are now tuned together (audit S8, S9).
- A test fails when any `GameRules` number setting has no value check, so a later setting can't skip one
  (audit S4).

### API

`GET /api/rules` keeps its path, sign-in, ETag and 304. `ClientRules` gains six fields: the five auto-end numbers and
the minimum loop area (O11). No other endpoint, no database change, no migration, no SignalR change.

### Server ↔ phone contract

| C# `ClientRules` | JSON | Dart `GameRules` | Type |
|---|---|---|---|
| `AutoEndVehicleSpeedMetersPerSecond` | `autoEndVehicleSpeedMetersPerSecond` | `autoEndVehicleSpeedMetersPerSecond` | double |
| `AutoEndVehicleSeconds` | `autoEndVehicleSeconds` | `autoEndVehicleSeconds` | int |
| `AutoEndStillRadiusMeters` | `autoEndStillRadiusMeters` | `autoEndStillRadiusMeters` | double |
| `AutoEndStillSeconds` | `autoEndStillSeconds` | `autoEndStillSeconds` | int |
| `AutoEndStillMaxWalkedMeters` | `autoEndStillMaxWalkedMeters` | `autoEndStillMaxWalkedMeters` | double |
| `MinLoopAreaSquareMeters` (from `Loop:MinAreaSquareMeters`) | `minLoopAreaSquareMeters` | `minLoopAreaSquareMeters` | double (O11) |

- The five FR1 fields stay. The shared sample `tests/contracts/client_rules.json` gains the new ones, each with a value
  no other field has, and the whole sample passes the startup checks (audit S19).
- The phone test "the app never knows anti-cheat numbers" allows exactly `autoEndVehicleSpeedMetersPerSecond` and
  still fails on any other key with "speed" (audit S15).
- The test that the built-in copy matches `appsettings.json` compares every field by name, so a new field can't be
  missed (audit S20).
- **Deploy order:** server first. An old phone ignores the new fields (tested in FR1). A new phone with an old server
  rejects every reply and keeps its rules (audit S22) — written in the PR and `docs/status.md`.

## What FR2 changes in FR1 (tests, record, design doc)

FR1 is closed and frozen, so these are FR2's changes, made in the PR named, with the FR1 record updated in the same
PR (`myloop-closing-an-fr`, keeping records true). Each FR1 test keeps its "red when" proof.

**FR1 tests that change**

| Test | Why | New form | PR |
|---|---|---|---|
| `GameRulesTests.Value_at_its_upper_limit_is_allowed` (`MaxAverageSpeedMetersPerSecond, "15"`) | the vehicle speed must stay above it | raises the vehicle speed with it | 3/7 |
| `GameRulesTests.Value_at_its_upper_limit_is_allowed` (`AccuracyThresholdMeters, "200"`) | the still radius must be at least 1.5× it, and the walked cap above the still radius | raises the still radius to 300 and `StillMaxWalkedMeters` above 300 with it | 3/7 |
| `ClientRulesTests.Client_rules_contain_no_anti_cheat_numbers` | it fails on any name with "Speed" | allows exactly `AutoEndVehicleSpeedMetersPerSecond` | 3/7 |
| `ClientRulesTests` same-values test, `ContractTests`, `RulesHttpTests` | they list the fields by hand | cover the six new fields | 3/7 |
| `RulesModuleBoundaryTests` | a new public `AutoEndRules` class | added to the allowed public types | 3/7 |
| phone `contract_test` ("knows exactly the fields"), `game_rules_test` (built-in = `appsettings.json`, "no anti-cheat numbers") | the sample and `Version` change | the Dart model, built-in copy (version 2) and these tests move in the same PR as the server, so it merges green | 3/7 |
| `rules_consistency_test` walk tests (the walk keeps its rules, LIFE-1, LIFE-11, NET-3, LEG-8's exact 3 s D1, the permission dialog) | start now needs a signed-in user, reads the diary and writes `startTapped` (5/7), asks for notifications (6/7); `stopJourney` (5/7) and `requestPermission` (7/7) are replaced | a signed-in user with a fake diary and notifier; the 3 s limit still written out | 5/7, 6/7, 7/7 |

**FR1 record lines that change** (`records/fr1-game-rules.md`)
- "What shapes the app": Settings (`AutoEnd` group), Server module (public types), Startup check (lower limits and
  the two combination checks), API (eleven phone fields), Saved copy (O10 upgrade, tag dropped) — PR 3/7; Phone
  state (refresh "after a walk" now comes from `endWalk`), Walks (start also waits for the diary read, before the
  pin) — PR 5/7; Walks (start also waits for the notification ask, before the pin) — PR 6/7.
- "Decisions that must stay true": the minimum loop area is now sent to the phone (O11; FR1 had kept it server-only
  because the phone didn't use it) and "keeps the last rules the server sent" gains O10's exception — PR 3/7; "every
  phone field is required" gains the value floors (audit S6) — PR 4/7.
- "Left to later FRs → FR9": the fingerprint covers every `ClientRules` field — PR 3/7.
- "Known limits": loop claims sent mid-walk are judged by the server's rules at that moment (D2 per loop); claim
  sends inside `endWalk` and sign-out have their own limits — PR 5/7.
- "How to change a rule": `AutoEnd`'s lower limits, its own upper limits, and the two combination checks — PR 3/7.

**FR1 design doc** (`design/fr1-game-rules.md`): its Settings, Contract and Scenarios sections get a one-line note
"changed by FR2 — see `design/fr2-walk-session.md`" (five fields, 14 settings and version 1 become eleven fields, 19
settings and version 2; its LIFE-4 and GAME-15 rows are superseded by FR2's) — PR 3/7.

## Riverpod state impact

| Provider | New or changed | Holds | Reset when |
|---|---|---|---|
| `gameRulesProvider` | changed | the rules, now with the six new fields | never (FR1) |
| `journeyControllerProvider` | changed | walk state; one owner for start and end; the auto-end detector; the account's queue | sign-out (as today) |
| `walkDiaryStoreProvider` | new | the signed-in account's diary store (one writer) | account change (a new store for the new account; the old file stays) |
| `lastWalkEndProvider` | new | the last walk's end reason, end time, walk time, distance and what it captured, until dismissed | dismissed, or sign-out |
| `walkEndNotifierProvider` | new | `WalkEndNotifier` (real or fake) | never |

**Values in a saved copy** (audit S6): the phone checks only that each new field is a finite number above a hard
sanity floor (speed above 0, times at least 60 s, distances and the minimum loop area above 0, so a corrupt 0 can't
make every wobble a loop); a copy that fails is rejected like a wrongly typed one, so a corrupt "0 seconds" can't end
every walk at once. The real limits stay the server's alone: a test fails if any phone floor is tighter than the
server's lower limit, so widening a server limit later never locks installed phones on old rules.

**Saved rules after the app update** (audit S21, O10): an old saved copy without the new fields is no longer thrown
away. `RulesStore.load` keeps its server values and fills only the new fields (auto-end and the minimum loop area)
from the built-in copy, and **drops the saved tag**. The tag must go: with the server deployed first, an old app may
already have saved the new server's tag while ignoring the fields it didn't know, so keeping it would earn a 304 and
the phone would never get the server's values for the new fields. With no tag, the next refresh gets a full reply.
This keeps the FR1 decision "after an app update the phone keeps the last rules the server sent", with one exception
written into the FR1 record: new fields come from the built-in copy until that full reply.

## State consistency (every reader × every app moment)

State: the **walk diary** and the **account's step-claim queue file** (kept across launches), the **auto-end numbers
pinned for the walk**, the **waiting and failed loop claims** (in memory, for the walk), the **notifications
"asked" flag** (kept across launches), and FR1's **saved rules copy** (kept across launches, upgraded by O10). Readers:
**R1** the closed-app check at launch and login · **R2** the debug viewer · **R3** `endWalk` (writes) · **R4** the
auto-end detector (pinned numbers) · **R5** FR3's sender (later; FR2 only keeps the file for it) · **R6** FR1's
saved-rules loader (`RulesStore.load` and `gameRulesProvider`): its O10 rows get their tests in PR 3/7 and its value
floors row in PR 4/7 · **R7** the walk start's notification ask (O5, PR 6/7).

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
| App updated (saved rules without the new fields) | Server values kept, tag dropped; the new fields (auto-end and minimum loop area) from the built-in copy (R6) | old saved copy — red when the copy is thrown away or the old tag is kept |
| Corrupt line | Skipped, `diaryDamaged` shown in the viewer, no crash (R1, R2) | garbage line — red when reading throws |
| Two writers at once | One lock; no line lost (R3) | Stop and auto-end at the same moment — red when a line is missing or the walk ends twice |
| Disk full | Walk carries on; line written before the next one (R3) | write that throws, then works — red when the walk ends or the line is lost |
| Sign-out mid-walk | `ended signedOut` online and offline; waiting loops sent when online; failed loop claims lost until FR3; diary and queue kept (R3) | sign-out while walking — red when the diary or queue is cleared or no end line |
| Killed during a still warning or countdown | Relaunch ends the walk at the start of the still stretch if the diary shows one (`stillSince` in the `alive` line), else at the last `alive` fix (R1) | kill during the countdown — red when the still minutes are counted in the walk |
| Offline when a loop closes | Claim kept in memory and resent by `endWalk`; a rejection is not resent (R3) | network failure, 401, 408, 429 or 5xx then online — red when not resent; a 400 verdict (`ClaimsController` rejects every claim with 400) — red when resent |
| Login as another account | Only that account's diary is read (R1) | two accounts on one phone — red when the other's open walk is found |
| Account deleted | Diary deleted after the server confirms; kept when it fails (R3) | failed delete — red when the diary or queue is cleared |
| Server rules change mid-walk | Pinned auto-end numbers stay for the walk (R4) | refresh mid-walk — red when the detector reads the live rules |
| Offline | Diary works; start blocked with today's message until FR3 (R1, R3) | offline start — red when no `startFailed offline` line |
| Back online / reconnect, or a rules refresh fails (401, 5xx) | Accepted: FR1's tests cover the rules; the pinned auto-end numbers never change mid-walk (R4) | — |
| Two closed-app checks at once (launch and login on a cold start) | One `ended` line (R1) | both triggers together — red when the walk gets two end lines |
| A closed-app check that runs after the user tapped Start | The running walk is skipped (R1) | start a walk, then run the login check — red when the running walk gets an `ended` line |
| A start that failed, then relaunch | Not a closed walk: no `ended` line, no "ended early" (R1) | start fails offline, relaunch — red when "ended early" shows or an `ended` line is written |
| Killed mid-walk, relaunched: the result | Walk time from `startAt` to `endAt`, distance from the last `alive` line (R1) | relaunch with an open walk — red when the result shows 0:00 or the launch time |
| Queue file at sign-out, account switch, relaunch | Kept for its account (O9); account B never reads or sends account A's file | sign-out then B signs in and walks — red when B's drain sends A's points or A's file is cleared |
| Queue file at account deletion | Cleared only after the server confirms (O4) | failed delete — red when the queue is cleared |
| Phone on a table outdoors (no fixes, no error) | Ends as `autoEndedStill`, not `noGps`, with the still warnings (R4) | silent stream for 10 min — red when the reason is `noGps` |
| A send stuck at Stop or at sign-out | Stop gives up after `walkEndSendLimit` (30 s), sign-out after 5 s; the walk still ends (R3) | a claim that never answers — red when `endWalk` or sign-out waits past the limit |
| Old app saved the new server's tag, then the app updated | The upgraded copy has no tag, so the next refresh is a full reply with the server's auto-end values (R6) | saved v2 tag without the new fields — red when the refresh sends the tag and gets a 304 |
| Notifications asked at login, then a walk starts | No second ask (R7) | login ask then Start — red when the dialog shows again |
| Saved rules copy with a new field below its floor (a corrupt 0) | Rejected like a wrongly typed copy; the current rules stay (R6) | saved copy with `autoEndStillSeconds` 0 — red when it loads |
| Every #44 event | Each event is written by its own trigger (start tapped, started, start failed, alive, each end reason, GPS error, loop sent, loop rejected, end claim rejected, damaged line) and survives an app kill (R3) | one test per event through its real trigger, reading the file after a simulated kill — red when that event's write is removed |
| Account deletion mid-walk | `ended accountDeleted`; a failed deletion keeps the diary, and the next launch doesn't say "ended early" (R1, R3) | failed delete then relaunch — red when "ended early" shows |

## Risks

| Risk | Status |
|---|---|
| Land inside loops closed before a closed app ended the walk | Mitigated (O1): each loop is sent when it closes; a claim that failed offline is lost if the app then closes, until FR3 keeps it |
| Points sent during the stretch auto-end cuts off stay on the server | Accepted (O2): the server already rejects driving points, and a still phone adds almost none |
| A bus or city car under 35 km/h never trips the vehicle rule; its points are rejected meanwhile | Accepted by the owner in Gate 1 (35 km/h, CHEAT-6); the still and no-GPS rules end it if it stops |
| 10 minutes with no fixes (a long tunnel, an underground train, deep inside a building) ends a real walk as still | Accepted (O3): strict by owner decision; the neutral warnings come first ("We haven't seen you move…") |
| A coffee stop over 10 minutes ends the walk | Accepted (O3): there is no Pause; the user starts a new walk |
| iOS may suspend the app when no fix arrives, so the still check runs late | Mitigated: warnings and the "walk saved" message are scheduled ahead as notifications; the check re-runs on the next fix, resume and launch, and `endAt` comes from fix times. UNVERIFIED on a real phone — checked before PR 6/7 merges |
| Android stops the app when permission is revoked | Mitigated: the closed-app check reads the permission and gives the right reason |
| Unsent points cleared at sign-out | Fixed by O9: the account's queue file is kept; it is sent with that account's next walk until FR3 sends it at sign-in |
| The map polls hexes every 30 s during a walk, also in the background (audit W31) | Accepted until FR8, which rebuilds the live map; FR2 adds no polling |
| A partial wake lock is held for the whole walk (audit P28) | Accepted: our own `enableWakeLock: true` (`location_service.dart:71`), kept on purpose for background tracking; FR2 doesn't change it |
| Android 13+ hides the tracking notification when notifications are refused (audit P12) | Accepted: tracking still works; UNVERIFIED — checked on a real Android 13+ phone before PR 6/7 merges |
| A tuned anti-cheat limit can come within a hair of 35 km/h | Accepted: the owner chose "above" with no margin; the startup check stops anything at or past it |
| `flutter_local_notifications` clashes with firebase_messaging on iOS | Checked on a real iPhone before the notifications PR merges |
| Mock walks can't test permission loss, vehicle speed or no fixes | Tests fake GPS at the plugin's platform layer instead (LEG-3); the mock gets no FR2 features. In debug builds the mock's pause and speed buttons will now trigger auto-end — accepted for a dev tool |
| The phone's loop check could cut a loop at different points than the server | Mitigated: the phone copies the server's loop finding, area filter, constants and minimum loop area (O11), the shared loop paths (`tests/contracts/loop_paths.json`) fail when the two drift, and the end-of-walk claim still sends the whole path, so the server finds every loop; the cost is a rare rejected send |
| A loop driven at 30–35 km/h is still claimed (a loop claim has no times, and the vehicle rule starts at 35) | Accepted until FR6, whose server judges loops only from stored, speed-checked points (FR6 spec) |
| New users get no home, because set-home is skipped without location permission, so until FR6 their land more than 30 km from where they signed up decays in 7 days instead of 15–90 | Accepted when the owner merges PR 2/7: decay is old beta code that FR6 switches off (#43, `docs/data-removals.md`); within 30 km of home the decay is 7 days either way (`GameConstants.cs:66`); the other choice was keeping set-home's prompt with its own explain text, which leaves P7's lost first prompt |
| Distance XP counted twice for looped distance (each loop claim, then the whole-path claim) | Accepted: XP is old beta code no 0.1 FR owns yet, left until an FR rebuilds or removes it; hexes are never counted twice (the server skips owned hexes) |
| A claim or drain stuck in the sign-in token step (FR1 known limit) | Mitigated: `walkEndSendLimit` (30 s) and a 5 s limit at sign-out; every request gets a bounded wait in FR3 |

## Pull requests

| PR | What | Branch |
|---|---|---|
| 1/7 | Spec (Gate 1 and Gate 2 decisions), this design doc and the early blind audit report — docs only, about 900 lines, so it carries a `Size exception:` line the owner agrees to (the spec, the design and its audit are one approval). Merged as #237 | `v0.1/fr2-design-doc` |
| 2/7 | Docs only: the gaps a re-check on 2026-10-17 and its review found, fixed in this doc, the spec (#42's set-home line, FR3's list) and `docs/status.md` | `claude/funny-sagan-uwnkgz` (the session could push only there) |
| 3/7 | Server `AutoEnd` settings and checks, `ClientRules`, the `appsettings.json` comment, and in the same PR the phone's `GameRules` model, built-in copy (version 2), contract sample and their tests, so it merges green; the saved-copy upgrade (O10, tag dropped) with its matrix rows (R6), because the new required fields would otherwise make an updated app throw its saved server rules away; the FR1 tests, record lines and design-doc notes listed above. Before it merges: the indoor trace for `StillMaxWalkedMeters` (250 m, or 400 m), saved in `audits/` | `v0.1/fr2-server-settings` |
| 4/7 | Phone: value floors; walk diary store, `package_info_plus`, debug viewer with its testable debug flag; register row for the diary store | `v0.1/fr2-diary` |
| 5/7 | Phone: one start/end owner (start guard, one queue per account, `startTapped` first, `alive` lines, walk time from a stopwatch), `endWalk` with the whole-path claim, post-walk refresh, result (with walk time and distance) and send limits, `findLoops` with the shared loop paths (`tests/contracts/loop_paths.json`), Stop dialog, closed-app check (reason `appClosed` until 7/7); loops still sent only at Stop | `v0.1/fr2-walk-end` |
| 6/7 | Phone: auto-end detector, warnings and scheduled notifications (`flutter_local_notifications`), the notification ask at the first walk start (O5) with its "asked" flag, and loops sent as they close (needs the vehicle check) | `v0.1/fr2-auto-end` |
| 7/7 | Phone: `checkAccess()` and the permission flow (the GPS-off error, the first inaccurate fix and the check before the first still warning included), pre-prompt, set-home skipped when location isn't allowed or no position comes back, `accountDeleted` and the O4/O9 teardown changes (register rows for `user_session_teardown.dart` and `journey_controller.dart`, by method name), Info.plist, privacy manifest, compliance docs | `v0.1/fr2-permissions` |

Every merged PR leaves master working: features that need a later PR stay off until it lands, as written in each
row. 6/7 and 7/7 are the likely ones to pass ~15 files / ~400 lines; if so they split (renumbering every PR, as
`myloop-tasks-and-prs` says) rather than carry a size exception. Like FR1, the spec changes ride with the design doc:
they were written on the same branch, and on an FR branch "PR rules" lets a PR merge before its design doc only when
that PR adds the design doc.

**Checks outside the code, with where their result is kept:** the indoor trace for the walked cap (`audits/`, before
3/7 merges). Before 6/7 merges, on a real iPhone: a suspended app's scheduled warnings, `flutter_local_notifications`
next to firebase_messaging, and whether a `Stopwatch` keeps counting while the phone sleeps (audit P24; the walk
time on screen catches up from fix times either way, so only the auto-end counts depend on it); on a real Android
13+ phone: the hidden tracking notification (audit P12). Before 7/7 merges, on a real iPhone: precise location
turned off with the app in the background ends the walk as `preciseLocationOff`. Results go in the PR description of
the PR they gate and the FR2 record's Known limits at close-out. `docs/status.md` lists them under "Waiting on the
owner".

## Early blind audit

Report: `docs/versions/1/0.1/audits/2026-10-14-fr2-early-blind-audit.md` — three agents, 91 findings, run on
`8793a00` before this doc was written. Each finding is answered above (design, owner decision or risk) or in the
`## Scenarios` table; the new cases became rows there.

## Scenarios

Every ID in `docs/scenarios.md`, answered for FR2. `open #236` means FR2 builds and tests it; the test name is
filled in by the PR that adds it.

| ID | Status | Evidence |
|---|---|---|
| LIFE-1 | open | #236: start waits until the diary is read, so a closed walk is found first; a check that runs after Start skips the running walk |
| LIFE-2 | open | #236: no diary file means no open walk; start works as today |
| LIFE-3 | open | #236: a half-written diary line is skipped and the next write starts on a new line (audit W24) |
| LIFE-4 | open | #236: a closed app ends the walk at the still-stretch start or last `alive` fix (#45); completed loops were already sent; sending the killed walk's unsent points at launch is FR3's |
| LIFE-5 | open | #236: auto-end runs on fixes, a one-shot deadline and scheduled notifications in the background; the 30 s hex poll that keeps running is FR8's |
| LIFE-6 | open | #236: back to the app re-checks location access; removed, GPS off or precise off ends the walk |
| LIFE-7 | open | #236: diary lines carry `v`; an old saved rules copy keeps its server values and gets the new fields (auto-end and minimum loop area) from the built-in copy, with its tag dropped (audit S21) |
| LIFE-8 | open | #236: a bad diary line is skipped and shown as damaged in the debug viewer; a saved rules copy with out-of-range values in the new fields is rejected (audit S6); no crash |
| LIFE-9 | open | #236: one diary writer per account; one start or end at a time; one step-claim queue per account (audit W5, W22, W23) |
| LIFE-10 | open | #236: no walk length limit; every walk timer is cancelled in `endWalk` |
| LIFE-11 | open | #236: a start that fails at any step returns to "not walking" with a `startFailed` diary line (audit W2–W4), and the next launch never reports it as a closed walk |
| NET-1 | open | #236: the diary works offline; starting offline stays blocked with today's message until FR3, and leaves a `startFailed offline` line |
| NET-2 | open | #236: a loop claim that gets a 5xx is kept and resent by `endWalk` (rules failures stay FR1's) |
| NET-3 | open | #236: claim sends in `endWalk` share `walkEndSendLimit` (30 s) and sign-out's sends a 5 s limit, so a send stuck in the sign-in step can't hang either; every request's own limit is FR3's |
| NET-4 | open | #236: a loop claim that gets a 200 with an unreadable body is treated as a failure, kept and resent; FR1 covers the rules reply |
| NET-5 | open | FR3: sending diaries and a killed walk's points when back online |
| NET-6 | n/a | FR2 adds no new endpoint; a loop claim resent after a lost reply is folded into the same Claim and owned hexes are skipped (`TerritoryService.cs:96-118`) |
| NET-7 | open | #236: a claim that gets a 401 is kept and resent; a forced sign-out writes only a diary line |
| NET-8 | open | #236: a claim that gets a 403 or 404 is kept and resent by `endWalk`, never treated as a verdict |
| NET-9 | open | #236: a claim that gets a 429 is kept and resent by `endWalk` |
| NET-10 | open | #236: a rejected loop claim is final and never resent (diary `loopRejected`); a 4xx deleting a batch's points is FR3's (audit W34); the phone never deletes a diary because of a reply |
| NET-11 | open | #236: each `WalkEndReason` has its own message; none says "anti-cheat" |
| AUTH-1 | open | #236: sign-out ends the walk (`signedOut`, online and offline), sends loops still waiting for the vehicle check when online, keeps the diary and the account's queue file (O9) |
| AUTH-2 | open | #236: login reads only that account's diary file |
| AUTH-3 | open | #236: diary and queue files are named by user id; a new account starts with none; a deleted account's files are deleted after the server confirms (O4, `accountDeleted`) |
| AUTH-4 | open | FR12: guests don't exist yet |
| AUTH-5 | open | #236: a forced sign-out stops GPS, writes `signedOutForced` and then tears down as today, except that the account's queue file and diary are kept (O9) |
| AUTH-6 | n/a | FR2 doesn't touch sign-in |
| PRIV-1 | n/a | no new endpoint |
| PRIV-2 | n/a | no hub change |
| PRIV-3 | open | #236: diary lines hold no coordinates and FR2 code logs none; a test reads every event type for latitude/longitude fields |
| PRIV-4 | open | #236: the phone diary is deleted when the server confirms the account deletion; the server copy is FR12's |
| PRIV-5 | open | #236: the walk is stopped (GPS and drain) before the delete request; the diary writer's lock is held while the file is deleted |
| PRIV-6 | n/a | nothing about other players |
| PRIV-7 | n/a | the diary only holds the user's own events |
| DEV-1 | open | #236: `checkAccess()` never opens Settings; the screen explains and offers an "Open settings" button; restricted gets its own message; set-home no longer asks for location, so the first system prompt is the one at "Start walk", after the explain screen (audit W6, P7–P9) |
| DEV-2 | open | #236: stream error, stream end and resume run `checkAccess()`; Android's GPS-off error ends the walk at once, even if GPS is back on; location removed or GPS off ends the walk; Android's stop-on-revoke is caught by the closed-app check (audit P1–P4, P2) |
| DEV-3 | open | #236: precise location turned off mid-walk ends the walk (O6), found on the first inaccurate fix and before the first still or no-GPS warning too; asking for precise location before a walk is FR3's |
| DEV-4 | open | #236: notifications asked at the first walk start if never asked (O5); refusing never blocks; messages then show in the app only |
| DEV-5 | open | #236: a failed diary write keeps the line in memory and retries; the walk carries on; shown in the debug viewer; a failed or half-written queue save is FR3's (audit W24) |
| DEV-6 | open | #236: auto-end uses GPS fix times and a monotonic clock; the walk time on screen comes from a stopwatch that catches up from fix times, never the phone clock (audit W30, P24); the result's walk time is `endAt` minus the start's GPS time; diary times are UTC; the queue's phone-clock `capturedAt` stays FR3's (audit W21) |
| DEV-7 | open | #236: an OS kill is "app closed" (#45); a late auto-end check still ends at the fix time; the up-front warning is FR4's |
| DEV-8 | open | #236: auto-end adds one one-shot timer and a 1 s ticker only during a countdown; the controller's 1 s walk-time timer pauses while the app is in the background (audit W30); the `alive` diary line is at most once a minute |
| DEV-9 | open | #236: auto-end uses only fixes that pass the accuracy threshold; the first-fix filter is FR3's |
| DEV-10 | open | #236: vehicle needs the recorded path's average speed over 3 minutes, so one jump or burst can't trigger it and a jittering still phone can't either; `pos.speed` is never used |
| IN-1 | open | #236: every `AutoEnd` setting (five) is rejected at startup when NaN or Infinity |
| IN-2 | open | #236: each `AutoEnd` setting has a lower limit (speed above 0, 60 s, 300 s, 1.5× accuracy, 100 m walked) |
| IN-3 | open | #236: each `AutoEnd` setting has an upper limit chosen so auto-end still does something (60 km/h, 600 s, 300 m, 1800 s, 1000 m) |
| IN-4 | open | #236: a missing `AutoEnd` setting stops the server; the phone rejects a reply missing one of the six new fields |
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
| DATA-1 | open | #236: new register rows for `walk_diary_store.dart` and `user_session_teardown.dart`, added by hand (outside the script's folder), and the `journey_controller.dart` row's verdict changes with O9 |
| DATA-2 | n/a | searched: the FR2 section of `requirements.md` for promises without a number — none; "deleted only after the server confirms" is part of #44 |
| GAME-1 | n/a | FR2 doesn't change how loops capture (FR6) |
| GAME-2 | n/a | FR2 doesn't change how loops capture (FR6) |
| GAME-3 | n/a | FR2 doesn't change how loops capture (FR6) |
| GAME-4 | open | #236: jitter adds no distance (today's noise floor) and doesn't restart the still count inside the radius |
| GAME-5 | n/a | FR2 doesn't change loop limits (FR6) |
| GAME-6 | n/a | FR2 doesn't change crossing detection (FR6) |
| GAME-7 | open | #236: fixes arriving for 10 minutes with none passing the accuracy threshold end the walk as `noGps`; no fixes at all count as still (risk table); shorter gaps are FR4's |
| GAME-8 | n/a | FR2 doesn't change sending (FR3) |
| GAME-9 | open | #236: equal or backwards fix times are skipped by the auto-end checks |
| GAME-10 | open | #236: auto-end never deletes points; the server still judges them |
| GAME-11 | open | #236: Stop warns from the phone's own loop check, which uses the server's minimum loop area (O11), when the last stretch isn't closed; that stretch is never captured |
| GAME-12 | n/a | FR2 doesn't change exploration (FR7) |
| GAME-13 | open | #236: the phone's `findLoops` copies the server's loop finding, area filter and constants (earth radius, metres per degree), not its duplicate removal; the shared loop paths (`tests/contracts/loop_paths.json`) must give the same loops on both sides; the live preview stays FR8's |
| GAME-14 | open | #236: each loop is sent when it closes; `endWalk` resends failed ones and sends the whole path once as a safety net, then drains, within a time limit; keeping a failed claim across an app close is FR3's |
| GAME-15 | open | #236: no Pause (#32 dropped); vehicle (10 s warning) and still or no GPS (10 minutes, warnings at 5 minutes and in the last minute) end the walk, end time moved back, user told |
| GAME-16 | n/a | FR2 doesn't change exploration (FR7) |
| CHEAT-1 | open | #236: a loop is sent only after the vehicle check covered its last point; a loop under 35 km/h but over the server limit is FR6's, whose server judges loops only from stored points |
| CHEAT-2 | n/a | FR2 doesn't change timestamps sent to the server (FR3, FR5) |
| CHEAT-3 | n/a | FR2 doesn't change the server's step checks (FR5) |
| CHEAT-4 | accepted | owner, Gate 1: driving under the server limit is FR5's; a bus under 35 km/h doesn't auto-end |
| CHEAT-5 | n/a | FR2 doesn't change replay detection (FR5, FR6) |
| CHEAT-6 | open | #236: the only speed the phone gets is the 35 km/h auto-end speed, kept above both server limits at startup; the "no anti-cheat numbers" test allows exactly that field |
| LEG-1 | open | #236: searched: `journey_controller.dart`, `journey_screen.dart`, `location_service.dart`, `user_session_teardown.dart` — no confirm on Stop, end flow in the screen, jump to Settings, "Always" log, stream errors ignored; each fixed in FR2. Offline start block: FR3 |
| LEG-2 | open | #236: the "Always" log and the unused "Always" purpose string (if geolocator doesn't need it, O8) are removed |
| LEG-3 | open | #236: GPS faked at the plugin's platform layer and time with a fake clock; the mock walk is not used to test FR2 |
| LEG-4 | open | #236: FR2 tests in `mobile/test/v0_1/fr2/` and `tests/MyLoop.V01.Tests`, run by CI |
| LEG-5 | open | #236: searched: every caller of `stopJourney` and `abandonForSignOut` (journey screen, session teardown) — all go through `endWalk`; the auto-end numbers are read only from the pinned rules |
| LEG-6 | open | #236: `/dev/walk-diary` and its button exist only in debug builds; the router takes the debug flag as a parameter so a test builds a release router and finds neither |
| LEG-7 | open | #236: `docs/learnings/phase-1.md`'s privacy-manifest lesson is picked up by O8; no other lesson is about walks |
| LEG-8 | open | #236: auto-end tests use a fake clock and check the exact limits (3:00, 10:00, the 5:00 warning and the 9:00 countdown, one millisecond either side) |
| LEG-9 | n/a | no CI change beyond adding tests |
| LEG-10 | open | #236: the diary and auto-end are their own classes; `journey_controller.dart` only wires them |
| LEG-11 | n/a | no secrets |
| LEG-12 | open | #236: no "Pause" text in the app outside the debug mock walk (searched `mobile/lib`) |
| API-1 | open | #236: the six new fields, each with the unit in the name, double/int as in the contract table, tested against `tests/contracts/client_rules.json` |
| API-2 | open | #236: the server is the one source; the built-in copy is compared with `appsettings.json` field by field; the loop maths copied into `findLoops` is checked by the shared loop paths (GAME-13) |
| API-3 | open | #236: `RulesHttpTests` checks the six new fields over real HTTP |
| STORE-1 | open | #236: `app-store-compliance` on the notifications and permissions PRs; privacy manifest and purpose strings (O8) |
