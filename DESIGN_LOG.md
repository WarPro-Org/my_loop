# MyLoop — Design Log

How the game actually works. One subsystem per entry, concise: **how it works → what it affects → open questions.** Mode: **local only, not pushed.**
Status: 🔵 in progress · 🟢 locked · ⚪ not started.

---

## 01 — Progression & PvP model  🔵

**Verified now (code):** `Level` (XP, only rises, unlocks nothing) + `Tier` (current hexes, caps 3,000 — seed users already 6–7k). To be replaced by the model below.

**Settled**
- **World = Safe.** Solo territory can't be stolen, only decays → **shield/steal-cap system dropped.**
- Three things, one job each:

| Thing | Its one job | Earned from |
|---|---|---|
| **Hexes (account)** | Territory → map, leaderboard, clan strength, XP income | Solo collect; net-new captures in duels/wars |
| **Trophies** | Rank → divisions + matchmaking | Duels/wars (win +, lose −) |
| **XP / Level** | Cosmetics only (never power) | All activity |

- **Divisions sit on Trophies**; matchmaking = same trophy-tier.

**Modes**

| Mode | How it works | Affects |
|---|---|---|
| **Solo collect** | Real world, persistent. Walk → take neutral/decayed land → kept (only decay removes it). | +Hexes, +XP, exploration, missions, streak |
| **Duel** | Opt-in, same-tier, 6h, **fresh 0-start scoreboard** on the same real streets. Every hex walked = duel point (own hexes included, re-collected fresh); hexes never owned before also added to account. Higher score wins. | ±Trophies→division, +XP, cosmetics; +Hexes (net-new only) |
| **War** | Duel, but clan vs clan. | +Clan trophies, +clan XP, member contribution; +Hexes (net-new only) |

**Open (block lock)**
- **O11** — confirm "different map" = separate scoreboard on the *same* real streets (not a second geography).
- **O12** — duel fairness: same-tier ≠ equal geography/free-time. Accept / match-by-density / **score by net-new only** (rec).
- **O13** — confirm loss = −trophies (needed for a real ladder).

**Deferred:** curves (hex→division thresholds, XP→level), seed-data fix, XP cosmetic scope, clan mechanics (entry 02).

---

## 02 — Clans  ⚪  (clan strength = members' Hexes; wars award Clan trophies)
## 03 — Territory wars  ⚪  (mechanics = team duel; see 01)
## 04 — XP cosmetics  ⚪
