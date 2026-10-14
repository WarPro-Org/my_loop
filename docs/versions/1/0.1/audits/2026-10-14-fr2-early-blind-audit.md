# FR2 — early blind audit (branch `claude/great-pasteur-b4y728` at `8793a00`, 2026-10-14)

Three agents searched one area each for every way FR2 can go wrong. Each read only the FR2 (and FR1) sections of
`requirements.md`, the FR1 record, `docs/scenarios.md` and the code — never the FR2 design doc or the task.
Paths are under `mobile/` unless they start with `api/` or `docs/`. "Plugin" = checked in the geolocator plugin
source at the versions in `pubspec.lock`. Every finding is answered in the design doc
(`design/fr2-walk-session.md`): in its design, its owner decisions, or its `## Scenarios` table.

## Area 1 — the walk on the phone and the diary

| # | Finding | Evidence | ID |
|---|---|---|---|
| W1 | No diary or app-version code exists; the app version needs a new package | no `package_info*` in `pubspec.yaml` | #44 |
| W2 | A start that fails after `status: tracking` leaves "Recording" with nothing recording | `journey_controller.dart:227`, `:237`, `:241-243` | LIFE-11 |
| W3 | A walk with no user id runs with every point dropped | `journey_controller.dart:334-335`, `:364` | LIFE-11 |
| W4 | The walk id is made only after the reachability check, permission, first fix and rules wait, so failed starts can't be written to a diary | `journey_controller.dart:200-225` | LIFE-11 |
| W5 | The controller has no guard against a second start; only the screen has one | `journey_controller.dart:188`, `journey_screen.dart:1163-1176` | LIFE-9 |
| W6 | Opening the map asks for location and jumps to Settings on "denied forever" | `journey_screen.dart:385-386`, `location_service.dart:117-119` | DEV-1 |
| W7 | A comment and an "Always" purpose string contradict "While using is enough" | `location_service.dart:123-129`, `ios/Runner/Info.plist:56` | LEG-2, STORE-1 |
| W8 | Notification permission is asked at login, not at walk start; no local-notification package | `login_screen.dart:263`, `push_notification_service.dart:21` | DEV-4 |
| W9 | Stop ends the walk at once, no confirmation | `journey_screen.dart:54-71` | #33 |
| W10 | A short walk is dropped with "Walk a bit more" and leaves no record | `journey_screen.dart:74-77` | GAME-14 |
| W11 | The loop claim is sent only if the server preview saw a loop, and is lost if it fails | `journey_screen.dart:86`, `:121-122` | GAME-14 |
| W12 | Sign-out, forced sign-out and account deletion delete the walk's unsent points; no loop claim | `user_session_teardown.dart:138-141`, `journey_controller.dart:487-491`, `:523` | AUTH-1, AUTH-5 |
| W13 | A failed account deletion still wipes the walk's unsent points | `user_session_teardown.dart:57-63` | PRIV-5 |
| W14 | Closing the screen leaves the walk running; the end-of-walk flow is tied to the screen | `journey_screen.dart:269`, `:112-114` | LIFE-11 |
| W15 | GPS stream errors and stream end are not handled; nothing re-checks permission on resume | `journey_controller.dart:239`, `realtime_resync.dart:54` | DEV-2, LIFE-6 |
| W16 | The mock walk can't test permission loss or stream end; its debug Pause sends still fixes | `mock_location_service.dart:36`, `mock_walk_runner.dart:114-124,151` | LEG-3 |
| W17 | No auto-end code exists | — | GAME-15 |
| W18 | The next launch can't tell a walk was running; the walk id is only in memory | `journey_controller.dart:155` | LIFE-4 |
| W19 | "Last seen alive" can't come from points: a still user writes none for 30+ minutes | `app_constants.dart:15`, `journey_controller.dart:305-311` | LIFE-4 |
| W20 | A killed walk's points are sent only when the next walk starts | `journey_controller.dart:333-360` | LIFE-4, NET-5 |
| W21 | Points carry phone time, not GPS time; the path keeps no time | `journey_controller.dart:285`, `:370` | DEV-6 |
| W22 | A stopped walk's drain can overwrite the next walk's first points (two queue instances, one file) | `journey_controller.dart:337-338`, `:440`, `step_claim_queue.dart:110-114` | LIFE-9 |
| W23 | The diary will hit the same two-writer trap unless it has one owner | — | LIFE-9 |
| W24 | A failed append is an unhandled error; a half line spoils the next one | `journey_controller.dart:292`, `step_claim_queue.dart:90`, `:130-136` | DEV-5, LIFE-8 |
| W25 | A failed rewrite can send points twice and leaves a `.tmp` file | `step_claim_queue.dart:112-113`, `:157-159` | DEV-5, NET-6 |
| W26 | Queue lines have no format version; a changed field skips every old line | `step_claim_queue.dart:192-199` | LIFE-7 |
| W27 | File names from user ids can collide (`a.b` and `a_b`) | `step_claim_queue.dart:83-84` | AUTH-1 |
| W28 | After a forced sign-out nothing can send that account's saved walk, and its files never go away | `user_session_teardown.dart:174-180` | AUTH-5 |
| W29 | The diary must read the walk's pinned rules, and the version alone doesn't name a rule set | `journey_controller.dart:222`; FR1 record (FR9 item) | SRV-1 |
| W30 | Elapsed time uses the phone clock and a 1 s timer that runs in the background | `journey_controller.dart:589-597` | DEV-6, DEV-8 |
| W31 | The map polls hexes every 30 s during walks, in the background too | `journey_screen.dart:322-325` | DEV-8 |
| W32 | Leftover points wait for the next walk; `drainBeforeCapture` has no caller | `batch_drain_service.dart:30,80-90`, `journey_controller.dart:417-420` | GAME-14, LEG-2 |
| W33 | The 30-minute still rule may not fire on iOS while the app is suspended (UNVERIFIED) | `location_service.dart:71` | DEV-7 |
| W34 | Any 4xx deletes the batch's points from the phone | `batch_drain_service.dart:177-188` | NET-10 |
| W35 | The Stop warning has no reliable source: only a walk-wide loop count from the server preview | `journey_screen.dart:1209` | GAME-11 |
| W36 | New rules fields need the server first; the built-in copy and contract sample must gain them | `game_rules.dart:24-38,53-59` | IN-4, IN-5, API-1, API-2 |
| W37 | The debug viewer needs the same `kDebugMode` gate as the mock-walk screen | `lib/app/router.dart:82-83` | LEG-6 |

## Area 2 — the auto-end settings and how they reach the phone

| # | Finding | Evidence | ID |
|---|---|---|---|
| S1 | km/h compared with m/s passes any value; the phone's `pos.speed` is m/s | `appsettings.json:60-61`, `journey_controller.dart:305` | IN-7, API-1 |
| S2 | Times bound as `TimeSpan` read "3" as 3 days and reach the phone as text | `GameRulesValidator.cs:32`, `game_rules.dart:25-29` | API-1, IN-4 |
| S3 | A double on one side and an int on the other makes every phone reject a tuned value | `game_rules_provider.dart:135-137` | API-1 |
| S4 | Value checks are hand-written per setting; no test fails when one is missing | `GameRulesValidator.cs:11-12`, `GameRulesTests.cs:69-101` | IN-2, IN-3, LEG-3 |
| S5 | No lower limits: 3 s vehicle time ends walks on a GPS jump; 1 min still ends them at a red light | `GameRulesValidator.cs:32-36` | IN-2, IN-7 |
| S6 | The phone checks types only, never values, in a saved copy | `game_rules.dart:24-38` | LIFE-8 |
| S7 | 5× upper limits make auto-end useless (175 km/h, 150 min) | — | IN-3 |
| S8 | The anti-cheat speed cap (15 m/s) is now unreachable; a test and the FR1 record become false | `GameRulesValidator.cs:20`, `GameRulesTests.cs:125`, FR1 record | IN-7 |
| S9 | Only 0.72 m/s between 35 km/h and the shipped average limit; the two settings are now coupled | `appsettings.json:61` | IN-7 |
| S10 | "Above" with no gap still gives the limit away closely | — | CHEAT-6 |
| S11 | A bus or city car at 25–34 km/h never trips the vehicle rule; the server rejects its points meanwhile | — | CHEAT-4 |
| S12 | Still radius equal to the accuracy threshold passes "not below", and jitter can reset the count | `appsettings.json:57` | IN-7 |
| S13 | Laps of a small park could stay inside the still radius, depending on the anchor | — | GAME-15 |
| S14 | Still detection must use raw fixes, not the noise-filtered path | `journey_controller.dart:279-282` | LEG-5, GAME-4 |
| S15 | A test fails on any rules key containing "speed" | `game_rules_test.dart:81-87` | CHEAT-6 |
| S16 | The settings comment says only Loop and Gps are sent; the new group must not live in AntiCheat | `appsettings.json:48` | CHEAT-6, LEG-2 |
| S17 | Nothing forces `Version` up; the diary can't tell which values ended a walk | `appsettings.json:49`, `game_rules.dart:51` | SRV-1 |
| S18 | The fingerprint covers only `ClientRules`; the FR1 record's "4 phone settings" line becomes false | `RuleSettings.cs:28-40` | SRV-2 |
| S19 | The contract sample must pass the startup checks, with a unique value per field | `RulesHttpTests.cs:61-75`, `ContractTests.cs:18-23` | API-1, API-3 |
| S20 | The drift test between the built-in copy and the server lists fields by hand | `game_rules_test.dart:65-79` | API-2 |
| S21 | After the app update the saved copy lacks the new fields, is thrown away, and the phone drops to built-in rules — against an FR1 decision | `rules_store.dart:52-60` | LIFE-7 |
| S22 | A new phone with an old server rejects every reply | `game_rules_provider.dart:135` | SRV-2 |
| S23 | Auto-end must read the pinned `_walkRules`, never the live provider | `journey_controller.dart:222` | SRV-1 |

## Area 3 — permissions, GPS and auto-end detection

| # | Finding | Evidence | ID |
|---|---|---|---|
| P1 | Android: GPS off arrives as `LocationServiceDisabledException`; a quick toggle's meaning is unset | plugin `FusedLocationClient.java:86-93` | DEV-2 |
| P2 | Android kills the app when permission is revoked, so the walk ends as "app closed" with the wrong reason | Android behaviour (UNVERIFIED) | DEV-2 |
| P3 | iOS sends one generic error for permission removed and GPS off; the app must check after any error | plugin `GeolocationHandler.m:184-199` | DEV-2 |
| P4 | iOS service-status stream reports only the global switch, never the app's permission | plugin `LocationServiceStreamHandler.m:36-46` | DEV-2 |
| P5 | Precise location turned off mid-walk drops every fix silently; the walk ends 30 min later as "still" | `journey_controller.dart:272-275` | DEV-3 |
| P6 | Android stream can stay silent if the service isn't bound; no watchdog | plugin `StreamHandlerImpl.java:107-110` | LIFE-11 |
| P7 | iOS maps the first "Don't allow" to denied forever, and the first prompt is spent in onboarding | plugin `AuthorizationStatusMapper.m:16-17`, `set_home_screen.dart:40-43` | DEV-1 |
| P8 | iOS Restricted (parental controls) gets "allow in settings", which the user can't do | plugin `AuthorizationStatusMapper.m:13-15` | DEV-1 |
| P9 | Raw exception text; no "open settings" action; "disabled" found by string match | `location_service.dart:101-120` | DEV-1 |
| P10 | Offline is checked before permission | `journey_controller.dart:199-205` | NET-1 |
| P11 | `POST_NOTIFICATIONS` comes only from firebase_messaging's manifest | plugin manifest, `AndroidManifest.xml:7-10` | DEV-4 |
| P12 | Android 13+: refusing notifications hides the tracking notification (UNVERIFIED) | Android behaviour | DEV-4 |
| P13 | Android 14+: restarting the location service from the background can throw (UNVERIFIED) | Android behaviour | LIFE-11 |
| P14 | iOS keeping a "While using" app alive with no fixes is UNVERIFIED; the timer may not fire | `Info.plist:58-61` | LIFE-5, DEV-7 |
| P15 | Both plugins forward only the newest fix of a batch | plugin `GeolocationHandler.m:160-175`, `FusedLocationClient.java:70` | DEV-10 |
| P16 | No local-notification package; its iOS delegate may clash with firebase_messaging (UNVERIFIED) | `pubspec.yaml:30-51` | STORE-1 |
| P17 | The in-app message is a one-shot field shown only by the journey screen, so it is lost if the user is elsewhere | `journey_controller.dart:124`, `journey_screen.dart:174` | DEV-4 |
| P18 | The end-of-walk flow lives in the screen, so an auto-end can't claim loops | `journey_screen.dart:54-128` | GAME-14, GAME-15 |
| P19 | A missing speed reads as 0, so a rule on `pos.speed` never fires; `pos.speed >= 0` is dead | plugin `position.dart:164,188-191`, `journey_controller.dart:305` | DEV-10, LEG-2 |
| P20 | Speed from fixes fakes high values on jumps; equal or backwards times divide by zero | — | DEV-10, GAME-9 |
| P21 | "Faster than 35 km/h for 3 minutes" is not defined (per fix or average?) | — | GAME-15 |
| P22 | A tunnel or underground train has no fixes while fast | — | GAME-7 |
| P23 | The still rule has no anchor, and no rule for rejected fixes | — | GAME-15 |
| P24 | The elapsed clock jumps with the phone clock; a `Stopwatch` may stop in sleep (UNVERIFIED) | `journey_controller.dart:223,594` | DEV-6 |
| P25 | Fix times aren't kept, so start (phone clock) and end (GPS clock) can disagree | `journey_controller.dart:370` | DEV-6, API-1 |
| P26 | Moving the end time back doesn't undo points, hexes or loops from the stretch | `journey_controller.dart:285-292,379-412` | SRV-8 |
| P27 | Still from the very start gives a zero-length walk | — | GAME-15 |
| P28 | A partial wake lock is held for the whole walk; auto-end should use one-shot deadlines | plugin `GeolocatorLocationService.java:195-203` | DEV-8 |
| P29 | The privacy manifest is still missing | `docs/compliance/apple-review-checklist.md` | STORE-1 |
| P30 | The compliance checklist says to drop background tracking; the When-In-Use string doesn't mention screen-off tracking | `Info.plist:54-57` | STORE-1 |
| P31 | No pre-prompt before the system location or notification dialogs | `set_home_screen.dart:40-43`, `login_screen.dart:263` | STORE-1 |
