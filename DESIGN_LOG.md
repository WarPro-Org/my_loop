# MyLoop — Design Log

How the game actually works. One subsystem per entry, concise: **how it works → what it affects → open questions.** Mode: **local only, not pushed.**
Status: 🔵 in progress · 🟢 locked · ⚪ not started.

---

## 01 — Progression & PvP model  🔵

**Verified now (code):** `Level` (from XP, only rises, unlocks nothing) + `Tier` (from current hexes, caps at 3,000 — but seed users already hold 6–7k). Two ladders, no clear jobs.

**Settled**
- One hex counter = **current hexes** (live). "Max ever" = vanity stat only.
- **XP = cosmetics/status only**, never power.

**Proposed model — three things, one job each**
| Thing | Its one job | Earned from |
|---|---|---|
| **Hexes** | Territory → map, leaderboard, clan strength, XP income | Solo walking; winning duels/wars |
| **Trophies** | Competitive rank → divisions/tiers + matchmaking | Duels (win +/ lose −) |
| **XP / Level** | Cosmetic unlocks | All activity |

**Modes → what they affect**
| Mode | You do | Affects |
|---|---|---|
| Solo collect | Walk, take neutral/decayed land | +Hexes, +XP, exploration, missions, streak |
| Matchmade duel | Opt-in 6h race vs skill-matched foe | ±Trophies → division, +XP, cosmetic reward |
| Clan war | Team vs team | +Clan trophies, clan XP, member contribution |

**Open forks (block lock)**
- **O9 — World safety:** Open (steal by walking through anyone's hex; needs shield + tier-gating) vs **Safe** (PvP only in opt-in duels/wars). *Rec: Safe* — deletes shield system, protects newbies/sleepers free.
- **O10 — Divisions on Trophies (skill) or Hexes (territory)?** *Rec: Trophies.* Reverses earlier "divisions = hexes" — hex count rewards dense-city geography + hoarding, not skill.
- **O11 — Duel format:** matched players are in different real places, so a duel = **parallel race** (each captures in own area 6h, more wins), not fighting over shared land. Confirm.

**Deferred until forks close:** shield numbers (only if Open world), division/XP curves, seed-data fix, XP cosmetic scope.

---

## 02 — Clans  ⚪  (clan strength consumes Hexes; clan wars award Clan trophies)
## 03 — Territory wars  ⚪
## 04 — XP cosmetics  ⚪
