# MyLoop — Design Log

How the game actually works. One subsystem per entry, concise: **how it works → what it affects → open questions.** Mode: **local only, not pushed.**
Status: 🔵 in progress · 🟢 locked · ⚪ not started.

---

## 01 — Progression & PvP model  🔵

**Verified now (code):** `Level` (XP, only rises, unlocks nothing) + `Tier` (current hexes, caps 3,000 — seed users already 6–7k). To be reworked.

**Three maps**

| Map | Stealable? | Shield? | Decay? | Persists? |
|---|---|---|---|---|
| **Solo** | Yes (neighbors) | **Yes** | Yes | Yes — your real territory |
| **Duel** | No | No | Resets each duel | Only **net-new** hexes → solo (with decay) |
| **War** | No | No | Resets each war | Only **net-new** hexes → solo (with decay) |

Duel/war = same real streets, **per-event overlay that resets to 0**; re-walking owned hexes scores for the event; any never-owned hex also lands in solo. Enables 3 duels/day on the same area.

**Three things, one job each**

| Thing | Job | Earned from |
|---|---|---|
| **Hexes (account)** | Territory → map, leaderboard, clan strength, XP income | Solo collect; net-new in duels/wars |
| **Trophies** | Rank → divisions + matchmaking (same-tier) | Duels/wars (win +, lose −) |
| **XP / Level** | Cosmetics only (never power) | All activity |

**Settled**
- Solo = **open world + shield** (shield params re-open: O2/O6 from earlier).
- Divisions on **Trophies** (rec), not hex count.
- **Duel AND war = independent capture** (no contention): co-located players, same or rival clan, each capture the same hex for their own score. Score = sum of what each collects.
- **Live opponent progress** shown during duels/wars (tension without proximity).

**Duel/war strategy (depth beyond "collect most")**
| Lever | Decision it adds | Built? |
|---|---|---|
| Loops score big (close loop → interior) | route-planning > raw steps | ✅ exists |
| Bonus/objective hexes (5× spawns) | detour vs sweep tradeoff | new, easy |
| Best-of-3 objectives (most hexes / biggest loop / most net-new) | comeback; less density dominance | new (defer past v1) |
*Rec for v1: loops + bonus hexes + live bar. Skip best-of-3 initially.*

**Open (block lock)**
- **O13 — War team strategy:** independent+sum = no coordination. Add clan **contiguity/coverage bonus** so being a team matters? Or accept wars = sum of solo effort?
- **O14 — "net-new"** = hex the *player* never owned (assumed) — confirm.
- **O15 — Loss = −trophies?** confirm (needed for ladder).

**Deferred:** shield numbers (solo), curves (hex→division, XP→level), seed fix, XP cosmetic scope, clans (entry 02).

---

## 02 — Clans  ⚪  (clan strength = members' Hexes; war = team duel, shared map)
## 03 — Territory wars  ⚪  (see 01 — shared contested overlay)
## 04 — XP cosmetics  ⚪
