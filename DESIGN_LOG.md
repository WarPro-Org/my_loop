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

**Open / grilling (block lock)**
- **O11 — Duel contention:** parallel/independent (step-race, geography decides) vs match-nearby (real head-to-head, needs density)? 
- **O12 — Duel is thin:** no opponent interaction + re-walk same block 3×/day = repetitive. Mitigate with **live opponent progress** (rec). Accept the loop?
- **O13 — War vs duel inconsistency:** war = shared contested (first-come locks hex, even across rival clans); duel = independent. Intentional?
- **O14 — "net-new" definition:** hex the *player* never owned, or one **no one** ever owned globally?
- **O15 — Loss = −trophies** (needed for a real ladder)? confirm.

**Deferred:** shield numbers (solo), curves (hex→division, XP→level), seed fix, XP cosmetic scope, clans (entry 02).

---

## 02 — Clans  ⚪  (clan strength = members' Hexes; war = team duel, shared map)
## 03 — Territory wars  ⚪  (see 01 — shared contested overlay)
## 04 — XP cosmetics  ⚪
