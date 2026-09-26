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
| FR2 | Walk session: start, pause, stop | Nothing can be recorded until a walk exists. |
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

Every tunable number lives in one place so the rules can be tuned from real test walks without code changes.

- **[#20]** Numbers are settings, not written into the code. Changing a setting applies to future walks only; past
  results never change silently.
- FR1 builds the settings system and moves the numbers today's code uses: loop-closing distance, minimum loop
  points and size, GPS accuracy threshold, and the anti-cheat speed checks. Exact values are tuned from real test walks.
- Each later FR adds its own settings when it is built: auto-end thresholds (FR2), short-gap limits and safety-alarm
  delay (FR4), guest inactivity period (FR12).
- The old claim minimums (10 GPS points, 200 m walked) stay in code until FR6 replaces the old claim code.

Depends on: nothing.

## FR2 — Walk session: start, pause, stop

- **[#30]** A walk starts only when the user taps "Start walk". There is no automatic start — location is tracked only
  while a walk is running.
- **[#42]** A walk can't start without the location permission it needs (and notification permission for the safety
  alarm, which the user can decline). If location permission is removed mid-walk, the walk ends and is saved, and the
  app tells the user why.
- **[#31]** Standing still doesn't break a walk (coffee, traffic lights, a chat).
- **[#32]** There is a Pause button. Nothing is recorded while paused. On resume, if the user is within the
  loop-closing distance of where they paused, the loop carries on; otherwise the loop starts fresh. How long the pause
  lasted doesn't matter.
- **[#33]** A walk ends when the user taps "Stop".
- **[#34]** A forgotten walk ends automatically if the user moves at vehicle speed for a few minutes, or barely moves
  for a long time (around 30 minutes). The app notifies them that the walk was saved.
- **[#35]** When a walk ends, these are kept: explored hexes, any loops closed during the walk, and the walk record
  (path, distance, time). Land from an unfinished last stretch that never closed is not captured.

Depends on: FR1.

## FR3 — GPS recording and offline sync

- **[#9]** Every GPS point is saved on the phone straight away and sent to the server when there's internet. The
  server decides what you captured, not the phone.
  - Until the server has confirmed a walk (e.g. it was recorded offline), its result is shown as a clearly labelled
    estimate ("Waiting to sync").
- **[#7]** (recording part) GPS points below the accuracy threshold are ignored. Capturing needs precise location: if
  the user has only allowed approximate location, the app explains why and asks for precise location before a walk
  can start.
- **[#12]** Weak GPS is flagged at that moment — as a message on screen, or in the tracking notification when the app is
  in the background — with no buzz.
- Tracking keeps working with the screen off, the phone in a pocket, or another app (e.g. WhatsApp) open.

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

Depends on: FR2, FR3.

## FR5 — Anti-cheat speed checks

- **[#13]** Walking and running count. Anything faster (cycling, driving) doesn't.
  - In 0.1 this is a speed limit only, around 20–25 km/h. We accept that slow cycling can slip through, because
    single-player cheating mostly fools the cheater.
  - The version that adds rivals also uses the phone's motion sensor (walking / running / cycling / driving) to catch
    cycling at running speed.
- **[#14]** Speed checks also cover gaps, so drive-and-walk tricks don't work.
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
  - Loops below the minimum size (GPS jitter while standing still, walking up one side of a street and back down the
    other) capture nothing.
- **[#7]** (rule part) Accuracy means the rule is applied 100% correctly, and the path is as good as the phone's GPS
  allows. "100% correct" is proven by a set of reference walks with known correct results; the capture rule must
  reproduce them exactly, every time.
- In 0.1, capturing never loses land: land already owned stays owned (see FR15).

Depends on: FR1, FR3.

## FR7 — Exploration

- **[#5]** Walking anywhere reveals the map. A hex becomes "explored" when the path passes through it — including the
  stretch between two recorded points, not only the hex a point landed in. Explored land is yours to see, not owned,
  and nobody can steal it.
  - Sections rejected as too fast, and long gaps that aren't joined up, explore nothing.

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

Depends on: FR5, FR6, FR7.

## FR9 — Walk history and storage

- **[#19]** Every walk is saved in full from day one: every GPS point with its time, plus the result the server decided
  at the time and which version of the rules decided it. Any future rule (e.g. land strength) can be calculated from
  this history.
  - Walks are kept for as long as the account exists and are deleted with it (see FR12).
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
    walks, explored hexes and land move into the existing account, and the guest account is deleted.
- **[#22]** Guests can walk, explore and capture. When rivals arrive, a guest's land stays private and can't take anyone
  else's until they sign in.
- **[#40]** Deleting an account deletes everything — walks, captured land, explored hexes and the passport. Nothing is
  left behind.

Depends on: FR9, FR10.

## FR13 — Moving existing beta users to 0.1

- **[#23]** No home location. `HomeLocation.cs` and everything that uses it are removed end to end, including stored home
  coordinates.
- **[#41]** Fresh start for existing beta testers: accounts, display names and avatars stay; captured land, explored hexes
  and saved home locations are deleted. Testers see a one-time message: "MyLoop has been rebuilt — your map starts
  fresh."

Depends on: FR6, FR7 (new rules live before the reset).

## FR14 — Onboarding

- **[#24]** Three short intro cards ("Walk a loop", "Everything inside becomes yours", "Others can take it back"); everyone
  sees them once per account.

Depends on: nothing.

## FR15 — Land strength (recorded now, designed with rivals)

In 0.1 no land is ever lost and strength is not shown. FR9 records full walk history, so these rules can be added later
without rework. The details and numbers are decided when rivals are designed.

- **[#16]** Walking a hex makes it stronger, up to a limit.
- **[#17]** Strength fades after a grace period if you stop walking there.
- **[#18]** One walk brings it back.

No 0.1 work beyond FR9.

---

## Open — to be decided later

- Exact values of every FR1 setting — tuned from real test walks.
- Area boundary data source, licence and attribution (FR10) — design stage.
- Rival rules (how land is taken, how strength defends it, FR15) — designed in a later 0.x version, before 1.0.

## Coverage — every requirement and its feature

| ID | Feature | ID | Feature | ID | Feature |
|----|---------|----|---------|----|---------|
| #1 | Scope | #15 | FR5 | #29 | FR10 |
| #2 | FR6 | #16 | FR15 | #30 | FR2 |
| #3 | FR6 | #17 | FR15 | #31 | FR2 |
| #4 | FR6 | #18 | FR15 | #32 | FR2 |
| #5 | FR7 | #19 | FR9 | #33 | FR2 |
| #6 | FR6 | #20 | FR1 | #34 | FR2 |
| #7 | FR3 + FR6 | #21 | FR12 | #35 | FR2 |
| #8 | FR8 | #22 | FR12 | #36 | FR8 |
| #9 | FR3 | #23 | FR13 | #37 | FR11 |
| #10 | FR4 | #24 | FR14 | #38 | FR11 |
| #11 | FR4 | #25 | FR10 | #39 | FR9 |
| #12 | FR3 | #26 | FR10 | #40 | FR12 |
| #13 | FR5 | #27 | FR10 | #41 | FR13 |
| #14 | FR5 | #28 | FR10 | #42 | FR2 |
