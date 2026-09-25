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

- Requirements are grouped by **feature** (F1, F2, …). Each feature is meant to become one task, and everything that
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
| F1 | Configurable game settings | Every rule below reads its numbers from here. |
| F2 | Walk session: start, pause, stop | Nothing can be recorded until a walk exists. |
| F3 | GPS recording and offline sync | The raw path every later feature works on. |
| F4 | Tracking gaps and safety alarm | Makes the recorded path trustworthy when tracking breaks. |
| F5 | Anti-cheat speed checks | Removes invalid sections before anything is captured or explored. |
| F6 | Loop detection and capture rule | The core of the game — built on a clean, validated path. |
| F7 | Exploration | Uses the same validated path; feeds the passport. |
| F8 | Live preview and result screen | Shows the results of F5–F7 to the user. |
| F9 | Walk history and storage | Stores full walks and results; re-opens the result screen. |
| F10 | Areas and passport | Counts explored hexes from stored walk results. |
| F11 | Profile | Displays totals from F9 and the passport from F10. |
| F12 | Accounts: guests, sign-in, deletion | Merge and delete must cover everything above. |
| F13 | Moving existing beta users to 0.1 | Run once the new rules are live, just before testers get 0.1. |
| F14 | Onboarding | Independent and small; can be done any time, listed last. |
| F15 | Land strength | No 0.1 work beyond F9 — designed with rivals. |

---

## F1 — Configurable game settings

Every tunable number lives in one place so the rules can be tuned from real test walks without code changes.

- **[#20]** Numbers are settings, not written into the code. Changing a setting applies to future walks only; past
  results never change silently.
- The 0.1 settings are: loop-closing distance (also used for resuming after a pause), minimum loop size, short-gap
  time and distance limits, GPS accuracy threshold, speed limit, auto-end thresholds (vehicle-speed duration, idle
  duration), safety-alarm delay, and guest inactivity period. Exact values are tuned from real test walks.

Depends on: nothing.

## F2 — Walk session: start, pause, stop

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

Depends on: F1.

## F3 — GPS recording and offline sync

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

Depends on: F1, F2.

## F4 — Tracking gaps and safety alarm

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

Depends on: F2, F3.

## F5 — Anti-cheat speed checks

- **[#13]** Walking and running count. Anything faster (cycling, driving) doesn't.
  - In 0.1 this is a speed limit only, around 20–25 km/h. We accept that slow cycling can slip through, because
    single-player cheating mostly fools the cheater.
  - The version that adds rivals also uses the phone's motion sensor (walking / running / cycling / driving) to catch
    cycling at running speed.
- **[#14]** Speed checks also cover gaps, so drive-and-walk tricks don't work.
- **[#15]** Only the section that was too fast is rejected, not the whole walk. The app tells the user ("This section was
  too fast to count") but never reveals the exact speed limit.

Depends on: F1, F3.

## F6 — Loop detection and capture rule (server)

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
- In 0.1, capturing never loses land: land already owned stays owned (see F15).

Depends on: F1, F3.

## F7 — Exploration

- **[#5]** Walking anywhere reveals the map. A hex becomes "explored" when the path passes through it — including the
  stretch between two recorded points, not only the hex a point landed in. Explored land is yours to see, not owned,
  and nobody can steal it.
  - Sections rejected as too fast, and long gaps that aren't joined up, explore nothing.

Depends on: F3, F4, F5.

## F8 — Live preview and result screen

- **[#8]** No surprises:
  - a live preview during the walk shows the hexes you'd capture;
  - the server is the only judge of what is captured. The phone's preview is a close estimate of the same rule (without
    the anti-cheat checks), and an automated test replays real recorded walks and fails if the preview and the server
    ever disagree;
  - weak GPS is flagged at that moment (see F3);
  - the result screen shows the path over the captured hexes.
- **[#36]** The result screen shows how close an unfinished loop came to closing ("You were 150 m from closing this
  loop"), with the gap drawn on the map.
- The result screen also shows what was explored, and any section rejected as too fast (see F5).

Depends on: F5, F6, F7.

## F9 — Walk history and storage

- **[#19]** Every walk is saved in full from day one: every GPS point with its time, plus the result the server decided
  at the time and which version of the rules decided it. Any future rule (e.g. land strength) can be calculated from
  this history.
  - Walks are kept for as long as the account exists and are deleted with it (see F12).
- **[#39]** Opening a past walk from walk history shows the same result screen as when it ended: the path, what was
  captured, what was explored, and any "you were X m from closing" hint.

Depends on: F6, F7, F8.

## F10 — Areas and passport

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

Depends on: F7, F9.

## F11 — Profile

- **[#37]** The profile shows: total land captured, hexes explored, total distance, number of walks, and the passport.
- **[#38]** The profile also keeps what exists today: display name, avatar and colour, edit name, walk history,
  notification settings, contact support, sign out, and delete account.

Depends on: F9, F10.

## F12 — Accounts: guests, sign-in, deletion

- **[#21]** People can try a walk as a guest. A guest is a real user in the database, kept permanently once they link
  Apple or Google.
  - Unlinked guests are deleted after a period of inactivity.
  - If the Apple or Google account a guest links already belongs to a MyLoop user, the two are merged: the guest's
    walks, explored hexes and land move into the existing account, and the guest account is deleted.
- **[#22]** Guests can walk, explore and capture. When rivals arrive, a guest's land stays private and can't take anyone
  else's until they sign in.
- **[#40]** Deleting an account deletes everything — walks, captured land, explored hexes and the passport. Nothing is
  left behind.

Depends on: F9, F10.

## F13 — Moving existing beta users to 0.1

- **[#23]** No home location. `HomeLocation.cs` and everything that uses it are removed end to end, including stored home
  coordinates.
- **[#41]** Fresh start for existing beta testers: accounts, display names and avatars stay; captured land, explored hexes
  and saved home locations are deleted. Testers see a one-time message: "MyLoop has been rebuilt — your map starts
  fresh."

Depends on: F6, F7 (new rules live before the reset).

## F14 — Onboarding

- **[#24]** Three short intro cards ("Walk a loop", "Everything inside becomes yours", "Others can take it back"); everyone
  sees them once per account.

Depends on: nothing.

## F15 — Land strength (recorded now, designed with rivals)

In 0.1 no land is ever lost and strength is not shown. F9 records full walk history, so these rules can be added later
without rework. The details and numbers are decided when rivals are designed.

- **[#16]** Walking a hex makes it stronger, up to a limit.
- **[#17]** Strength fades after a grace period if you stop walking there.
- **[#18]** One walk brings it back.

No 0.1 work beyond F9.

---

## Open — to be decided later

- Exact values of every F1 setting — tuned from real test walks.
- Area boundary data source, licence and attribution (F10) — design stage.
- Rival rules (how land is taken, how strength defends it, F15) — designed in a later 0.x version, before 1.0.

## Coverage — every requirement and its feature

| ID | Feature | ID | Feature | ID | Feature |
|----|---------|----|---------|----|---------|
| #1 | Scope | #15 | F5 | #29 | F10 |
| #2 | F6 | #16 | F15 | #30 | F2 |
| #3 | F6 | #17 | F15 | #31 | F2 |
| #4 | F6 | #18 | F15 | #32 | F2 |
| #5 | F7 | #19 | F9 | #33 | F2 |
| #6 | F6 | #20 | F1 | #34 | F2 |
| #7 | F3 + F6 | #21 | F12 | #35 | F2 |
| #8 | F8 | #22 | F12 | #36 | F8 |
| #9 | F3 | #23 | F13 | #37 | F11 |
| #10 | F4 | #24 | F14 | #38 | F11 |
| #11 | F4 | #25 | F10 | #39 | F9 |
| #12 | F3 | #26 | F10 | #40 | F12 |
| #13 | F5 | #27 | F10 | #41 | F13 |
| #14 | F5 | #28 | F10 | #42 | F2 |
