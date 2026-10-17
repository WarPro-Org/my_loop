---
type: requirements
title: MyLoop — Version 0.1 Functional Requirements
project: my-loop
status: draft
role: requirements
author: robin
date: 2026-09-24
tags: [requirements, v0.1, single-player, capture-accuracy]
---

# MyLoop — Version 0.1 Functional Requirements

High-level functional requirements agreed in the fresh redesign discussion.
Tracked by [WarPro-Org/my_loop#198](https://github.com/WarPro-Org/my_loop/issues/198).
This is the "what", not the "how". Where it conflicts with `docs/product/spec.md`,
this document wins (notably: trail cells no longer capture territory; home location is removed).

## How this document is organised

- Requirements are grouped by **feature** (FR1, FR2, …). Each feature is meant to become one task, and everything that
  feature needs is listed under it.
- Each requirement keeps its permanent ID in brackets, e.g. `[#30]`. IDs are not reading order; new requirements get
  the next free number. The coverage table at the end lists every ID and the feature that owns it.
- Features are numbered in build order (see **Build order**). "Depends on" says which features must exist first.

## Scope of 0.1

**[#1]** Versions 0.x are internal steps; 1.0 is the first public release on the App Store and Play Store.
- **0.1 (this document) is single-player only.** In 0.1 every user's land and exploration is visible only to that user.
- Later 0.x versions (up to 0.9) add rivals and everything else 1.0 needs.
- 1.0 must include rivals.

## Build order

Features are numbered in the order they should be built. Each one only depends on features above it.

| Order | Feature | Why here |
|-------|---------|----------|
| FR1 | Configurable game settings | Every rule below reads its numbers from here. |
| FR2 | Walk session: start and stop | Nothing can be recorded until a walk exists. |
| FR3 | GPS recording and offline sync | The raw path every later feature works on. |
| FR4 | Tracking gaps and safety alarm | Makes the recorded path trustworthy when tracking breaks. |
| FR5 | Anti-cheat speed checks | Removes invalid sections before anything is captured or explored. |
| FR6 | Loop detection and capture rule | The core of the game — built on a clean, validated path. |
| FR7 | Exploration | Uses the same validated path; feeds the passport. |
| FR8 | Live preview and result screen | Shows the results of FR5–FR7 to the user. |
| FR9 | Walk history and storage | Stores full walks and results; re-opens the result screen. |
| FR10 | Areas and passport | Counts explored hexes from stored walk results. |
| FR11 | Profile | Displays totals from FR9 and the passport from FR10. |
| FR12 | Accounts: guests, sign-in, deletion | Merge and delete must cover everything above. |
| FR13 | Moving existing beta users to 0.1 | Run once the new rules are live, just before testers get 0.1. |
| FR14 | Onboarding | Independent and small; can be done any time, listed last. |
| FR15 | Land strength | No 0.1 work beyond FR9 — designed with rivals. |

---

## FR1 — Configurable game settings

**Status:** done (task #201), closed again 2026-10-07 after the 2026-09-29 blind audit reopened it; its list is frozen, and anything found later goes to the FR that owns that code. What it built and what later FRs must keep true: `records/fr1-game-rules.md`.

Every tunable number lives in one place so the rules can be tuned from real test walks without code changes.

- **[#20]** Numbers are settings, not written into the code. Changing a setting applies to future walks only; past
  results never change silently.
- FR1 builds the settings system and moves the numbers today's code uses: loop-closing distance, minimum loop
  points and size, GPS accuracy threshold, and the speed numbers today's anti-cheat uses. Exact values are tuned from
  real test walks.
- Every number setting except `Version` has an upper limit, so a typo (500 instead of 50) stops the server at
  startup instead of running with it: at most 5× its shipped value, except the two rate settings, which are capped
  at 1. `Version` has none, as it only grows. `NaN` and `Infinity` are rejected too.
- Each later FR adds its own settings when it is built: auto-end thresholds (FR2), short-gap limits and safety-alarm
  delay (FR4), speed checks over gaps (FR5), guest inactivity period (FR12).
- The old claim limits (e.g. 10 GPS points, 200 m walked, 20 walks a day) stay in code until FR6 replaces the old
  claim code.
- A walk starts on the newest rules the server has, if the app can fetch them within 3 seconds; otherwise on the
  rules the app already has. The phone keeps a walk's rules for the whole walk.
- A rules request gives up after 30 seconds, sign-in token step included, so a stuck request never blocks later
  ones. A refused reply (any 4xx or 5xx) keeps the current rules and the saved copy; the app asks again only at the
  next trigger (app start, resume, login, reconnect, walk start), never in a loop of its own.
- Left to later FRs (agreed with the owner):
  - Until FR9 stores each walk's rules (version and fingerprint), the server judges a walk's points by the rules it has when they
    arrive, so a server update in the middle of a walk changes how the rest of that walk is judged.
  - Only the phone drops GPS points below the accuracy threshold; the server check comes with FR3.
  - Guests (FR12) must be able to get the rules too; today `GET /api/rules` needs a signed-in user.
  - Moved out when the FR1 list was frozen, to the FR that rebuilds that code: the first GPS fix of a walk and the
    phone's noise floor (FR3), the hop-distance check and the smoothness minimums (FR5), `Loop:SkipNeighbors` and the
    loop-overlap number (FR6).

Depends on: nothing.

## FR2 — Walk session: start and stop

- **[#30]** A walk starts only when the user taps "Start walk". There is no automatic start — location is tracked only
  while a walk is running.
- **[#42]** A walk can't start without location permission. Notification permission (for walk-ended messages and the
  safety alarm) is asked but optional. If location permission is removed mid-walk, the walk ends and is saved, and the
  app tells the user why.
  - "While using the app" is enough on both phones; the app never asks for "Always". iPhone tracks in the background
    with the location background mode and the blue indicator; Android with a foreground service and its notification.
  - Notification permission is asked at the first walk start, unless it was already asked (today's login asks it for
    push). If the user says no, the walk still starts; warnings and walk-ended messages then show only inside the app.
  - A short screen explains why before the first system location prompt ("MyLoop uses your location only while you
    walk"). So that this is the first prompt, the sign-up screen that sets a home area no longer asks for location:
    it uses location only if already allowed and otherwise offers its "Skip for now" (home location is removed in
    FR13, #23).
  - If location is denied for good, the app explains how to fix it. It never jumps to Settings on its own (scenario
    DEV-1; today `location_service.dart` does).
  - The app checks the permission again when it comes back to the front. GPS turned off mid-walk, even briefly, and
    precise location turned off mid-walk count as removed: the walk ends at once and says which it was.
- **[#31]** Standing still for a short time doesn't break a walk (traffic lights, a short chat). Standing still for
  10 minutes ends it (#34).
- **[#32]** Dropped (owner decision, Gate 1 of FR2): there is no Pause button. A user who needs a break taps Stop and
  starts a new walk; stops under 10 minutes need nothing (#31, #34). Dropping it removes the resume rule and the
  walk splitting it needed.
- **[#33]** A walk ends when the user taps "Stop".
  - Stop asks "End walk?" first. If the current stretch hasn't closed a loop yet, it also says its land won't be
    captured.
    To know that reliably, the phone gets the server's minimum loop area as one more rule (owner, 2026-10-17); it is a
    loop rule, not an anti-cheat number.
- **[#34]** A walk ends automatically if the user moves at vehicle speed for a few minutes, or barely moves for 10
  minutes. The app warns first, then tells them the walk was saved. There is no way to cancel: riding a vehicle is
  never part of a walk, and there is no Pause.
  - Vehicle: faster than 35 km/h for 3 minutes. 35 is clearly a vehicle, above today's server limits (30 km/h top
    speed, 32.4 km/h average speed) and FR5's planned 20–25 km/h, so the phone, which must know it, gives nothing
    useful away about the server's limits (#15, scenario CHEAT-6). The server refuses to start unless the vehicle
    speed is above both of its own speed limits, so a later tuning can't raise a server limit to or past the phone's
    number (IN-7). The app then shows "Looks like you're in a vehicle. This walk ends in 10 s" with a countdown and no
    cancel; at zero the walk ends with the vehicle stretch taken out. The whole walk is never deleted: what was walked
    before the vehicle is kept (#35, #43), and the server already rejects every driving point.
  - Still: within 75 m of where the user stopped (measured from the average of the GPS fixes) and under 250 m of path
    walked, for 10 minutes, whether or not GPS fixes arrive. The 250 m cap stops laps of a small block counting as
    still; it is checked against a real indoor walk before release (400 m if jitter adds more). After 5 minutes still:
    "You've been still for 5 minutes. This walk ends in 5 minutes." After 9 minutes: a countdown from 60 to 0. Any
    real movement resets the count. With the app in the background the warnings come as notifications.
  - All five auto-end numbers (35 km/h, 3 min, 75 m, 250 m walked, 10 min) are settings of their own (FR1 rulebook).
    The still radius is not the loop-closing distance, so tuning loop closure never changes auto-end. The server
    refuses to start if the still radius is under 1.5× the GPS accuracy threshold, because then GPS jitter keeps
    resetting the count and a forgotten walk never ends (scenario IN-7).
  - The 3- and 10-minute counts run on the phone's elapsed-time clock (it keeps counting when no fixes arrive). The
    walk's end time is then moved back to the GPS time of the last fix before the fast or still stretch, so the
    stretch isn't counted in the walk's time or distance.
  - The message is a local notification when the app is in the background (a new notification package; FR4's alarm
    reuses it).
- **[#45]** If the app is closed mid-walk (the phone kills it, it crashes, or the phone restarts), the walk ends at its
  last recorded point, as if the user had tapped Stop then. Everything up to that point is kept (#35, #43); nothing
  after it counts. There is no resume. On the next launch the app tells the user the walk ended early and when.
  - So that completed loops survive a closed app, each loop is sent to the server as soon as the phone sees it close
    and the 3-minute vehicle check has covered it (a loop driven in a vehicle is never sent), not only at Stop. Only
    the open stretch since the last loop, and a loop closed in its last 3 minutes, can be lost. A loop that couldn't
    be sent (offline) is tried again when the walk ends; keeping it across an app close and resending it is FR3's. A
    loop the server rejects is not resent.
- **[#46]** Signing out mid-walk ends and saves the walk first. Each account's walks and diaries are kept apart on the
  phone, so the next person to sign in never sees or sends them (the lesson of bug #110).
  - Its unsent GPS points stay on the phone in that account's own file and go with that account's next walk (at
    sign-in from FR3); sign-out no longer deletes them. Deleting the account deletes them, but only after the server
    confirms the deletion: a failed deletion keeps the walk.
- **[#44]** Every walk has a diary, written to the phone the moment "Start walk" is tapped, so a walk that went wrong
  can be looked into later. It holds no locations, only:
  - walk ID, start and end time, rules version, app version, permissions at start;
  - every event with its time and reason: stopped by the user, auto-ended and why, location removed, GPS off, app
    closed (last time seen alive), signed out, start failed, no GPS for a while.

  FR2 writes the diary on the phone; FR3 sends it to the server; FR9 keeps it with the walk; FR12 deletes it with the
  account on the server. The phone deletes its copy only after the server confirms it has it, or when the account is
  deleted (FR2).
  - A diary that can't be written (phone full) never blocks or ends a walk: the line is kept in memory and tried again
    with the next one. The failure is logged and shown in the debug diary viewer, not to the user mid-walk (scenario
    DEV-5).
  - Until FR3 sends diaries, a debug-only screen shows them on the phone; release builds don't have it (scenario
    LEG-6).
- **[#35]** When a walk ends, these are kept: explored hexes, any loops closed during the walk, and the walk record
  (path, distance, time). Land from an unfinished last stretch that never closed is not captured.
- Left to later FRs (agreed with the owner):
  - Starting a walk offline stays blocked until FR3 (today `journey_controller.dart` refuses to start without the
    server). The diary itself works offline.

Depends on: FR1.

## FR3 — GPS recording and offline sync

- **[#9]** Every GPS point is saved on the phone straight away and sent to the server when there's internet. The
  server decides what you captured, not the phone.
  - Until the server has confirmed a walk (e.g. it was recorded offline), its result is shown as a clearly labelled
    estimate ("Waiting to sync").
- **[#7]** (recording part) GPS points below the accuracy threshold are ignored — by the server too, not only the
  phone (left open by FR1). Capturing needs precise location: if
  the user has only allowed approximate location, the app explains why and asks for precise location before a walk
  can start.
  - The first GPS fix of a walk goes through the accuracy threshold like every other fix (today it is taken before
    the walk's rules are pinned and skips it; moved from FR1, scenario DEV-9). The phone's noise floor (fixes closer
    than about 8 m are dropped) becomes a setting (LEG-5).
- Every request the app sends has a bounded wait, including the sign-in token step in the shared API client
  (`api_service.dart`), which can hang offline with an expired token. FR1 bounds only the rules request (found in
  FR1, scenarios LIFE-10 and NET-7).
- **[#12]** Weak GPS is flagged at that moment — as a message on screen, or in the tracking notification when the app is
  in the background — with no buzz.
- Tracking keeps working with the screen off, the phone in a pocket, or another app (e.g. WhatsApp) open.
- Walk diaries (#44, from FR2) are sent to the server with the walk's points, and the phone deletes its copy only
  after the server confirms it (or on account deletion, FR2). FR3 decides whether FR2's debug-only diary viewer
  stays once diaries reach the server. A walk can start offline (FR2 still blocks it).
- A loop claim that FR2 couldn't send (offline when the loop closed and when the walk ended) is kept on the phone,
  also across an app close and sign-out, for its own account only, and sent when back online (#45, #46, from FR2).
- Also left by FR2 (design `design/fr2-walk-session.md`, early blind audit):
  - each account's kept step-claim file (and a killed walk's unsent points) is sent at launch and at sign-in, not
    only with the next walk; files of accounts that never sign in again get a rule (audit W28);
  - queued points carry the GPS fix's time, not the time the phone saved them (DEV-6, audit W21);
  - a failed rewrite of the queue can send points twice and leave a `.tmp` file (audit W25), its lines have no
    format version (audit W26), a failed save of a point (phone full) is not caught, and a half-written line spoils
    the next point (audit W24);
  - a 4xx reply still deletes a batch's points from the phone (NET-10, audit W34).

Depends on: FR1, FR2.

## FR4 — Tracking gaps and safety alarm

- **[#10]** If tracking stops mid-walk:
  - a gap is joined up quietly only if it is short in both time and distance and implies walking or running speed;
  - otherwise the path before the gap can't close a loop with the path after it — the loop starts fresh and the app
    tells you;
  - loops already closed and hexes already explored before the gap are kept.
- **[#11]** Safety alarm (best effort): if tracking stops, the phone buzzes "tap to resume" within about 2 minutes. It's
  the only alert that buzzes during a walk.
  - iPhone: a scheduled local notification that the app keeps pushing back on a timer while tracking is alive (not only
    when a GPS point arrives, so standing still doesn't set it off).
  - Android: a persistent tracking notification plus the alarm where the phone allows it.
  - Backup: if a walk that was sending points to the server goes quiet, the server sends a push notification.
  - At the start of a walk, the app checks whether this phone can support the alarm. If it can't, the app tells the
    user up front and shows how to fix it (e.g. turn off battery optimisation for MyLoop).
  - Since FR2, 10 minutes with no GPS fix ends the walk (#34), so FR4's gap rules (#10) cover only shorter gaps.
  - Since FR2, a walk whose app was closed ends at its last point and can't be resumed (#45). FR4 decides what
    "tap to resume" means then (e.g. "Tracking stopped, your walk was saved. Tap to start a new one").

Depends on: FR2, FR3.

## FR5 — Anti-cheat speed checks

- **[#13]** Walking and running count. Anything faster (cycling, driving) doesn't.
  - In 0.1 this is a speed limit only, around 20–25 km/h. We accept that slow cycling can slip through, because
    single-player cheating mostly fools the cheater.
  - The version that adds rivals also uses the phone's motion sensor (walking / running / cycling / driving) to catch
    cycling at running speed.
- **[#14]** Speed checks also cover gaps, so drive-and-walk tricks don't work.
- The settings must agree: the fixed hop limit (`AntiCheat:MaxDistanceBetweenPointsMeters`) must be at least
  max speed × sampling interval + GPS drift, and the server refuses to start otherwise (moved from FR1, scenario
  IN-7). Today's values break this (60 m against 8.33 × 5 + 30 = 71.65 m), so FR5 sets them together with the new
  speed limit. The smoothness minimums in the path check become settings (LEG-5).
- **[#15]** Only the section that was too fast is rejected, not the whole walk. The app tells the user ("This section was
  too fast to count") but never reveals the exact speed limit.

Depends on: FR1, FR3.

## FR6 — Loop detection and capture rule (server)

- **[#6]** Closing a loop captures territory. This is the real prize, and it has to be accurate.
- **[#2]** A hex is captured if its **centre** is inside the loop. In practice, hexes more than about half inside usually
  count — but the rule is the centre, not the overlap area.
  - When a path crosses itself, it is split into simple loops. A hex counts if its centre is inside any of them (both
    halves of a figure-8 count).
- **[#3]** Hexes are H3 resolution 11: each side is about 29 m, so a hex is roughly 50–58 m across.
- **[#4]** A loop closes whenever the path crosses itself or comes back within the loop-closing distance of an earlier
  point of the same walk. One walk can close several loops.
  - `Loop:SkipNeighbors` does nothing today: loop detection already ignores the first `Loop:MinPoints` points, so any
    value from 0 to `MinPoints` (shipped: 10 and 20) has no effect. FR6 either gives it a meaning that shows at its
    shipped value, with a test at that value and its neighbours, or removes it from the server and the app together
    (moved from FR1, scenarios IN-6 and LEG-3). The loop-overlap number becomes a setting (LEG-5).
  - Loops below the minimum size (GPS jitter while standing still, walking up one side of a street and back down the
    other) capture nothing.
- **[#7]** (rule part) Accuracy means the rule is applied 100% correctly, and the path is as good as the phone's GPS
  allows. "100% correct" is proven by a set of reference walks with known correct results; the capture rule must
  reproduce them exactly, every time.
- **[#43]** In 0.1 no land and no explored hex is ever lost: not to another player's claim, to a timer, or to a server
  restart. Land already owned stays owned. This replaces the two prose promises that stood here and in FR15.
  - Old server code that breaks #43 today, which FR6 switches off (audit E5, `docs/data-removals.md`):
    - stealing: a claim hands a hex that another player owns to the claimant (`TerritoryService.cs`,
      `UpdateExistingCell`). In 0.1 such hexes are skipped and stay with their owner;
    - decay: an hourly job deletes land not walked through within its decay period, 7 to 90 days depending on
      distance from home (`DecayCleanupService.cs`, `GameConstants.cs`). The land part is removed; the
      streak-breaking part of the same job keeps running.
  - #43's "server restart" part is closed by FR7, which removes the startup step that deletes explored hexes.
- Loop claims are judged only from points the server stored and speed-checked, never from the path the phone sends,
  so a loop driven under FR2's 35 km/h vehicle rule but over the server's speed limit captures nothing (CHEAT-1; left
  open by FR2, which sends each loop as it closes).

Depends on: FR1, FR3.

## FR7 — Exploration

- **[#5]** Walking anywhere reveals the map. A hex becomes "explored" when the path passes through it — including the
  stretch between two recorded points, not only the hex a point landed in. Explored land is yours to see, not owned,
  and nobody can steal it.
  - Sections rejected as too fast, and long gaps that aren't joined up, explore nothing.
  - Old server code that breaks #5 and #43 today, which FR7 removes before it stores any exploration: whenever an owned
    hex has no explored row for its owner (seeded bot land, a stolen hex), the next server start deletes every player's
    explored hexes and rebuilds them from owned land only (`Data/DbInitializer.cs`, `BackfillExploredCells`, audit
    A2). FR7 removes the whole step: startup never deletes user data (scenario SRV-4).

Depends on: FR3, FR4, FR5.

## FR8 — Live preview and result screen

- **[#8]** No surprises:
  - a live preview during the walk shows the hexes you'd capture;
  - the server is the only judge of what is captured. The phone's preview is a close estimate of the same rule (without
    the anti-cheat checks), and an automated test replays real recorded walks and fails if the preview and the server
    ever disagree;
  - weak GPS is flagged at that moment (see FR3);
  - the result screen shows the path over the captured hexes.
- **[#36]** The result screen shows how close an unfinished loop came to closing ("You were 150 m from closing this
  loop"), with the gap drawn on the map.
- The result screen also shows what was explored, and any section rejected as too fast (see FR5).
- The preview and the server use the same limits: today the preview sends at most 500 points while the server
  allows 10,000, and distances use different earth radii (phone 6,378,137 m via geolocator, server 6,371,000 m;
  found in FR1, scenario GAME-13).
- The result screen also appears after a walk that didn't end with Stop: auto-end, a lost permission, a closed app
  (FR2 shows today's celebration for these until then).
- The live map stops polling for hexes while the app is in the background during a walk (today every 30 s; found in
  FR2, audit W31, LIFE-5).

Depends on: FR5, FR6, FR7.

## FR9 — Walk history and storage

- **[#19]** Every walk is saved in full from day one: every GPS point with its time, plus the result the server decided
  at the time and which version of the rules decided it. Any future rule (e.g. land strength) can be calculated from
  this history.
  - Walks are kept for as long as the account exists and are deleted with it (see FR12).
  - A walk is judged by the rules version it started with, also on the server, so a server update in the middle of a
    walk doesn't change how that walk is judged (#20; left open by FR1).
  - Each walk stores a fingerprint of the full rule set that judged it (every setting, including the server-only
    anti-cheat ones), not only the version number: a setting can change without a version bump, and FR1's fingerprint
    covers only the settings sent to the phone (#20; left open by FR1).
  - Each walk keeps its diary (#44, from FR2).
- **[#39]** Opening a past walk from walk history shows the same result screen as when it ended: the path, what was
  captured, what was explored, and any "you were X m from closing" hint.

Depends on: FR6, FR7, FR8.

## FR10 — Areas and passport

- **[#25]** Areas are real places (suburbs, cities) with their real names.
- **[#26]** Each area's boundary is saved once and frozen. A hex belongs to an area if its centre is inside the boundary.
  - Every hex belongs to exactly one area: the smallest named place it's in (usually a suburb).
  - Where the map data has no suburb, the hex falls back to the next level up (town or city).
  - Cities are the sum of their suburbs, so every hex is counted once and totals always add up.
- **[#27]** Every area has one fixed total hex count — everyone sees the same number, forever.
  - A saved boundary never changes.
  - If a real-world boundary changes, it is added as a new area. The old area stays in passports as it was (e.g.
    "Suburb A (until 2027)"), and new walks count toward the new area.
- **[#28]** A user's count in an area is the number of hexes they have **explored** there. It is always calculated from
  their saved walk results, never from a running counter that can drift. A faster cached copy is allowed only if it
  can be rebuilt from those results at any time.
- **[#29]** Passport: every user has a record of the areas they've explored and how much of each (e.g. "312 of 1,240
  hexes"). It lasts as long as the account, and in 0.1 only its owner can see it.
- Open for design: the boundary data source (e.g. OpenStreetMap, imported once rather than looked up live), its licence,
  and the attribution shown in the app.

Depends on: FR7, FR9.

## FR11 — Profile

- **[#37]** The profile shows: total land captured, hexes explored, total distance, number of walks, and the passport.
- **[#38]** The profile also keeps what exists today: display name, avatar and colour, edit name, walk history,
  notification settings, contact support, sign out, and delete account.

Depends on: FR9, FR10.

## FR12 — Accounts: guests, sign-in, deletion

- **[#21]** People can try a walk as a guest. A guest is a real user in the database, kept permanently once they link
  Apple or Google.
  - Unlinked guests are deleted after a period of inactivity.
  - If the Apple or Google account a guest links already belongs to a MyLoop user, the two are merged: the guest's
    walks (with their diaries, #44), explored hexes and land move into the existing account, and the guest account is
    deleted.
- Guests get the game rules like signed-in users (`GET /api/rules` must accept a guest; left open by FR1).
- **[#22]** Guests can walk, explore and capture. When rivals arrive, a guest's land stays private and can't take anyone
  else's until they sign in.
- **[#40]** Deleting an account deletes everything — walks, captured land, explored hexes and the passport. Nothing is
  left behind.
  - That includes walk diaries (#44) on the server; the phone copy is deleted since FR2.

Depends on: FR9, FR10.

## FR13 — Moving existing beta users to 0.1

- **[#23]** No home location. `HomeLocation.cs` and everything that uses it are removed end to end, including stored home
  coordinates.
- **[#41]** Fresh start for existing beta testers: accounts, display names and avatars stay; captured land, explored hexes
  and saved home locations are deleted. Testers see a one-time message: "MyLoop has been rebuilt — your map starts
  fresh."
- Bot users and their land, seeded today in every environment including Production (`Data/Seeding/`, audit A3), are
  deleted with the reset and no longer seeded outside development (scenario SRV-5).

Depends on: FR6, FR7 (new rules live before the reset).

## FR14 — Onboarding

- **[#24]** Three short intro cards ("Walk a loop", "Everything inside becomes yours", "Others can take it back"); everyone
  sees them once per account.

Depends on: nothing.

## FR15 — Land strength (recorded now, designed with rivals)

In 0.1 no land is ever lost (#43) and strength is not shown. FR9 records full walk history, so these rules can be added later
without rework. The details and numbers are decided when rivals are designed.

- **[#16]** Walking a hex makes it stronger, up to a limit.
- **[#17]** Strength fades after a grace period if you stop walking there.
- **[#18]** One walk brings it back.

No 0.1 work beyond FR9.

---

## Open — to be decided later

- Exact values of every game setting (FR1 and the settings later FRs add) — tuned from real test walks.
- Area boundary data source, licence and attribution (FR10) — design stage.
- Rival rules (how land is taken, how strength defends it, FR15) — designed in a later 0.x version, before 1.0.

## Coverage — every requirement and its feature

| ID | Feature | ID | Feature | ID | Feature |
|----|---------|----|---------|----|---------|
| #1 | Scope | #15 | FR5 | #29 | FR10 |
| #2 | FR6 | #16 | FR15 | #30 | FR2 |
| #3 | FR6 | #17 | FR15 | #31 | FR2 |
| #4 | FR6 | #18 | FR15 | #32 | dropped |
| #5 | FR7 | #19 | FR9 | #33 | FR2 |
| #6 | FR6 | #20 | FR1 + FR9 | #34 | FR2 |
| #7 | FR3 + FR6 | #21 | FR12 | #35 | FR2 |
| #8 | FR8 | #22 | FR12 | #36 | FR8 |
| #9 | FR3 | #23 | FR13 | #37 | FR11 |
| #10 | FR4 | #24 | FR14 | #38 | FR11 |
| #11 | FR4 | #25 | FR10 | #39 | FR9 |
| #12 | FR3 | #26 | FR10 | #40 | FR12 |
| #13 | FR5 | #27 | FR10 | #41 | FR13 |
| #14 | FR5 | #28 | FR10 | #42 | FR2 |
| #43 | FR6 | #44 | FR2 | #45 | FR2 |
| #46 | FR2 | | | | |
