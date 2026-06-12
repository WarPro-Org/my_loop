# MyLoop — Design Log

How the game actually works. One subsystem per entry, concise: **how it works → what it affects → open.** Mode: **local only, not pushed.**
Status: 🔵 in progress · 🟢 locked (model) · ⚪ not started.

---

## 01 — Player progression spine  🟢 model locked (numbers deferred)

**Three things, one job each**
| Thing | Its one job | Earned from |
|---|---|---|
| **Hexes (account)** | Territory → map, leaderboard, clan strength, XP income | Solo collect; net-new in duels/wars |
| **Individual trophies** | Individual division + duel matchmaking (same-tier) | Duels: win +, lose − |
| **XP / Level** | Cosmetics only (never power) | All activity |

**Three maps**
| Map | Stealable? | Shield? | Decay? | Persists? |
|---|---|---|---|---|
| Solo | Yes (neighbors) | **Yes** | Yes | Yes — real territory |
| Duel | No | No | Resets each duel | Only **net-new** → solo (w/ decay) |
| War | No | No | Resets each war | Only **net-new** → solo (w/ decay) |

**Duel** — opt-in, same-tier, 6h, **fresh 0-start** overlay on real streets; independent capture (no contention); re-walking owned hexes scores; **net-new = a hex the player never owned** → added to solo. Live opponent progress shown. Win/lose ±individual trophies.
**Strategy levers** (also used in wars): loops score big (close loop → interior; ✅ built) · bonus/objective hexes (5× spawns) · best-of-3 objectives (defer past v1).

---

## 02 — Clans  🔵

- Create/join; roles Leader/Officer/Member; clan chat.
- **Clan strength = members' Hexes** (drives clan leaderboard).
- **Clan trophies + clan division** ← wars (win +, lose −) → war matchmaking by clan division. *Independent of individual trophies.*
- **Open:** min level to create (anti-spam), max members, invite/kick rules, chat scope. → next session.

## 03 — Territory wars  🔵

- = **team duel**: independent capture, 0-start reset overlay, net-new → solo (w/ decay), strategy levers apply.
- **Affects:** clan trophies/division (win/lose); each member gets **+XP + net-new hexes only** (NOT individual trophies).
- **v1 = sum of members' effort** (no contiguity — unusable at launch density).
- **Deferred to v2:** clan **contiguity bonus** (connected member territory) — gated on local density / single-city launch.

## 04 — XP cosmetics  ⚪  (scope: hex skins, trail, claim FX, profile, map theme, level-gated clan create)

---

## Launch strategy (recommendation)
- **Launch single-city: Stockholm.** All multiplayer (duels, wars, clans, stealing, leaderboards) + future contiguity require local density. Scattered global launch = empty map. Note: Turf (Sweden) = proven appetite + direct competitor.

## Deferred tuning (numbers, after model)
Shield: X = clamp(% of holdings), max/floor hours, burn-per-capture · curves: Hex→division thresholds (raise past 7k), XP→Level · seed-data fix.
