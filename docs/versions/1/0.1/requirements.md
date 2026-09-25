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

Requirement numbers are permanent IDs, not reading order — new requirements get the next free number.

## Release plan

1. Versions 0.x are internal steps; 1.0 is the first public release on the App Store and Play Store.
   - **0.1 (this document) is single-player only.** In 0.1 every user's land and exploration is visible only to that user.
   - Later 0.x versions (up to 0.9) add rivals and everything else 1.0 needs.
   - 1.0 must include rivals.

## Capturing land

2. A hex is captured if its **centre** is inside your loop. In practice, hexes more than about half inside usually count — but the rule is the centre, not the overlap area.
   - When a path crosses itself, it is split into simple loops. A hex counts if its centre is inside any of them (both halves of a figure-8 count).
3. Hexes are H3 resolution 11: each side is about 29 m, so a hex is roughly 50–58 m across.
4. A loop closes whenever your path crosses itself or comes back within the loop-closing distance of an earlier point of the same walk. One walk can close several loops (e.g. a figure-8 around two blocks).
   - Loops below a minimum size (GPS jitter while standing still, walking up one side of a street and back down the other) capture nothing. The minimum size is a setting.
5. Walking anywhere reveals the map. A hex becomes "explored" when your path passes through it — including the stretch between two recorded points, not only the hex a point landed in. Explored land is yours to see, not owned, and nobody can steal it.
   - Sections rejected as too fast, and long gaps that aren't joined up, explore nothing.
6. Closing a loop captures territory. This is the real prize, and it has to be accurate.

## Accuracy

7. Accuracy means the rule is applied 100% correctly, and the path is as good as the phone's GPS allows.
   - "100% correct" is proven by a set of reference walks with known correct results; the capture rule must reproduce them exactly, every time.
   - GPS points below an accuracy threshold (a setting) are ignored.
   - Capturing needs precise location. If the user has only allowed approximate location, the app explains why and asks for precise location before a walk can start.
8. No surprises:
   - a live preview during the walk shows the hexes you'd capture;
   - the server is the only judge of what is captured. The phone's preview is a close estimate of the same rule (without the anti-cheat checks), and an automated test replays real recorded walks and fails if the preview and the server ever disagree;
   - weak GPS is flagged at that moment;
   - the result screen shows your path over the captured hexes.

## Tracking and safety

9. Every GPS point is saved on the phone straight away and sent to the server when there's internet. The server decides what you captured, not the phone.
   - Until the server has confirmed a walk (e.g. it was recorded offline), its result is shown as a clearly labelled estimate ("Waiting to sync").
10. If tracking stops mid-walk:
    - a gap is joined up quietly only if it is short in both time and distance and implies walking or running speed (all settings);
    - otherwise the path before the gap can't close a loop with the path after it — the loop starts fresh and the app tells you;
    - loops already closed and hexes already explored before the gap are kept.
11. Safety alarm (best effort): if tracking stops, the phone buzzes "tap to resume" within about 2 minutes. It's the only alert that buzzes during a walk.
    - iPhone: a scheduled local notification that the app keeps pushing back on a timer while tracking is alive (not only when a GPS point arrives, so standing still doesn't set it off).
    - Android: a persistent tracking notification plus the alarm where the phone allows it.
    - Backup: if a walk that was sending points to the server goes quiet, the server sends a push notification.
    - At the start of a walk, the app checks whether this phone can support the alarm. If it can't, the app tells the user up front and shows how to fix it (e.g. turn off battery optimisation for MyLoop).
12. Weak GPS shows as a message on screen or in the tracking notification, with no buzz.
42. A walk can't start without the location permission it needs (and notification permission for the safety alarm, which the user can decline). If location permission is removed mid-walk, the walk ends and is saved, and the app tells the user why.

## Starting and ending a walk

30. A walk starts only when the user taps "Start walk". There is no automatic start — location is tracked only while a walk is running.
31. Standing still doesn't break a walk (coffee, traffic lights, a chat).
32. There is a Pause button. Nothing is recorded while paused. On resume, if the user is within the loop-closing distance of where they paused, the loop carries on; otherwise the loop starts fresh. How long the pause lasted doesn't matter. This uses the same setting as the loop-closing distance.
33. A walk ends when the user taps "Stop".
34. A forgotten walk ends automatically if the user moves at vehicle speed for a few minutes, or barely moves for a long time (around 30 minutes). The app notifies them that the walk was saved.
35. When a walk ends, these are kept: explored hexes, any loops closed during the walk, and the walk record (path, distance, time). Land from an unfinished last stretch that never closed is not captured.
36. The result screen shows how close an unfinished loop came to closing ("You were 150 m from closing this loop"), with the gap drawn on the map.

## Anti-cheat

13. Walking and running count. Anything faster (cycling, driving) doesn't.
    - In 0.1 this is a speed limit only, around 20–25 km/h. We accept that slow cycling can slip through, because single-player cheating mostly fools the cheater.
    - The version that adds rivals also uses the phone's motion sensor (walking / running / cycling / driving) to catch cycling at running speed.
14. Speed checks also cover gaps, so drive-and-walk tricks don't work.
15. Only the section that was too fast is rejected, not the whole walk. The app tells the user ("This section was too fast to count") but never reveals the exact speed limit.

## Land strength (designed with rivals)

In 0.1 no land is ever lost and strength is not shown. Walk history is recorded from day one (#19), so the rules below can be added later without rework. The details are discussed when rivals are designed.

16. Walking a hex makes it stronger, up to a limit.
17. Strength fades after a grace period if you stop walking there.
18. One walk brings it back.

## Built to extend

19. Save every walk in full from day one: every GPS point with its time, plus the result the server decided at the time and which version of the rules decided it. Any future strength rule can be calculated from this history.
    - Walks are kept for as long as the account exists and are deleted with it (#40).
20. Numbers like the grace period, strength limit and speed limit are settings, not written into the code.
    - Changing a setting applies to future walks only. Past results never change silently.

## Accounts

21. People can try a walk as a guest. A guest is a real user in the database, kept permanently once they link Apple or Google.
    - Unlinked guests are deleted after a period of inactivity (a setting).
    - If the Apple or Google account a guest links already belongs to a MyLoop user, the two are merged: the guest's walks, explored hexes and land move into the existing account, and the guest account is deleted.
22. Guests can walk, explore and capture. When rivals arrive, a guest's land stays private and can't take anyone else's until they sign in.

## Profile

37. The profile shows: total land captured, hexes explored, total distance, number of walks, and the passport.
38. The profile also keeps what exists today: display name, avatar and colour, edit name, walk history, notification settings, contact support, sign out, and delete account.
39. Opening a past walk from walk history shows the same result screen as when it ended: the path, what was captured, what was explored, and any "you were X m from closing" hint.
40. Deleting an account deletes everything — walks, captured land, explored hexes and the passport. Nothing is left behind.

## Areas and passport

25. Areas are real places (suburbs, cities) with their real names.
26. Each area's boundary is saved once and frozen. A hex belongs to an area if its centre is inside the boundary.
    - Every hex belongs to exactly one area: the smallest named place it's in (usually a suburb).
    - Where the map data has no suburb, the hex falls back to the next level up (town or city).
    - Cities are the sum of their suburbs, so every hex is counted once and totals always add up.
27. Every area has one fixed total hex count — everyone sees the same number, forever.
    - A saved boundary never changes.
    - If a real-world boundary changes, it is added as a new area. The old area stays in passports as it was (e.g. "Suburb A (until 2027)"), and new walks count toward the new area.
28. A user's count in an area is the number of hexes they have **explored** there. It is always calculated from their saved walk results, never from a running counter that can drift. A faster cached copy is allowed only if it can be rebuilt from those results at any time.
29. Passport: every user has a record of the areas they've explored and how much of each (e.g. "312 of 1,240 hexes"). It lasts as long as the account, and in 0.1 only its owner can see it.

## Removed

23. No home location. `HomeLocation.cs` goes on the remove-or-park list. It is removed end to end, including stored home coordinates (see #41).

## Moving to 0.1

41. Fresh start for existing beta testers: accounts, display names and avatars stay; captured land, explored hexes and saved home locations are deleted. Testers see a one-time message: "MyLoop has been rebuilt — your map starts fresh."

## Minor

24. Intro cards: everyone sees them once per account.

## Open — to be decided later

- Exact numbers: loop-closing distance (also used for resuming after a pause), minimum loop size, short-gap limits, GPS accuracy threshold, speed limit, auto-end thresholds, guest inactivity period, grace period, strength cap — tune from real test walks.
- Area data source for real-place boundaries (e.g. OpenStreetMap, imported once rather than looked up live), including its licence and the attribution shown in the app — design stage.
- Rival rules (how land is taken, how strength defends it) — designed in a later 0.x version, before 1.0.
