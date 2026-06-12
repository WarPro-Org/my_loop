# MyLoop — Design Log

Living record of how the game actually works. **One subsystem per entry.** Each entry: verified current build → decisions + reasoning → open questions. We update this per decision; we do NOT pre-write conclusions.

Status keys: 🔵 in progress · 🟢 locked · ⚪ not started.

---

## 01 — Player progression spine  🔵 in progress

### Verified current build (facts from code)
- **Two unlinked ladders:** `Level` (from lifetime XP, only rises) and `Trophy/Tier` (from *current* hexCount, rises **and falls**). Diamond caps at **3,000** hexes. Level currently unlocks **nothing**.
- **Trophy tiers:** Bronze 0 · Silver 50 · Gold 200 · Platinum 500 · Crystal 1,500 · Diamond 3,000, each with 4 divisions (I–IV).
- **XP sources:** capture +10 · steal +25 · walk +50/km · active streak +20/day · all-3 daily missions +100 · achievements +25→+1000.
- **Known defects:** Trophy uses current hexCount → derank while offline. Seed users hold 6,200–7,100 hexes but Diamond caps at 3,000 → no headroom. Three competing "hex" numbers confuse the player.

### Decisions — 2026-06-12
- **D1 — Two distinct numbers.** `Peak hexes` (lifetime max, never drops) and `Current hexes` (live, stealable).
- **D2 — Badge/division = Peak hexes.** Permanent high-water mark. Kills derank-while-offline anxiety.
- **D3 — Current hexes = live stealable resource,** protected by a shield (D4).
- **D4 — Shield (Clash-of-Clans style).** After the shield is down, an attacker can steal up to **X** hexes; the victim then auto-receives an **adaptive shield whose duration scales with the fraction of X actually stolen** (steal 5 of 10 → 50% shield time). Params OPEN (O2).
- **D5 — (proposed, pending confirm) XP/Level = cosmetics + status ONLY.** Never buys power (no shield time, steal capacity, decay resistance). Protects fair competition.

### Open questions — must close before locking 🔵
- **O1 (critical) — What do `Current hexes` drive?** If the badge is on Peak (safe), defending/shield is pointless unless Current hexes drive something live. *Proposed:* leaderboard rank + clan contribution + XP income rate. **Needs owner decision.**
- **O2 — Shield params:** (a) base "100%" duration in hours? (b) is X per-attacker or total per window? (c) does attacking drop your own shield? (d) auto-shield for offline/new players?
- **O3 — Curves (after O1/D5 locked):** Peak-hex → division thresholds (raise ceiling well past 7k); XP → Level → cosmetic-unlock map. 
- **O4 — Fix seed data** to match final curves.
- **O5 — XP cosmetic scope:** which of {hex skins, trail effects, claim animation, profile cosmetics, map theme, level-gated clan creation}?

---

## 02 — Clans  ⚪ not started
(Depends on O1 — clan contribution may be a consumer of Current hexes.)

## 03 — Territory wars  ⚪ not started
## 04 — XP economy & cosmetic unlocks  ⚪ not started (depends on D5/O5)
