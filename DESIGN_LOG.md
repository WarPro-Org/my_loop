# MyLoop — Design Log

Living record of how the game actually works. **One subsystem per entry.** Each entry: verified current build → decisions + reasoning → open questions. We update this per decision; we do NOT pre-write conclusions.

> Working mode: **local only — not pushed.** Push once the full feature model is understood and agreed.

Status keys: 🔵 in progress · 🟢 locked · ⚪ not started.

---

## 01 — Player progression spine  🔵 in progress

### Verified current build (facts from code)
- **Two unlinked ladders:** `Level` (lifetime XP, only rises) and `Trophy/Tier` (current hexCount, rises **and falls**). Diamond caps at **3,000** hexes. Level unlocks **nothing**.
- **Trophy tiers:** Bronze 0 · Silver 50 · Gold 200 · Platinum 500 · Crystal 1,500 · Diamond 3,000, 4 divisions each (I–IV).
- **XP sources:** capture +10 · steal +25 · walk +50/km · streak +20/day · all-3 missions +100 · achievements +25→+1000.
- **Known defects:** Diamond caps at 3,000 but seed users hold 6,200–7,100 → no headroom. Level pays out nothing.

### Decisions — 2026-06-12/13
- **D1 — ONE hex counter.** `Current hexes` = single live, stealable number. `Max hexes ever` = vanity stat (profile only), drives nothing.
- **D2 — Badge/division = Current hexes** (CoC-style; volatile, can derank). *Reverses the earlier peak-based idea.* Valid ONLY because shield (D4) + matchmaking-replacement (R1/O7) exist.
- **D3 — Current hexes drive leaderboard rank + clan contribution + XP income.** (Earlier hole closed.)
- **D4 — Shield (CoC-style, adaptive).** Unshielded window: attackers collectively steal up to **X**; then a shield auto-applies, duration ∝ (stolen ÷ X). Numbers OPEN (O2).
- **D5 — Attacking burns your own shield,** scaled by activity while shielded (more capturing → faster burn). Numbers OPEN (O6).
- **D6 — XP/Level = cosmetics + status ONLY.** Never buys power. [scope pending O5]

### Critical realization — 2026-06-13
- **R1 — NO matchmaking exists. Attacks are physical/geographic.** Whoever walks through your hexes can raid you, any tier, online or asleep. CoC's "only similar tiers attack you" is impossible to copy. Therefore newbie + offline protection must come from **shields and/or tier-gated stealing**, not matchmaking.

### Proposed numbers (all tunable — awaiting owner reaction)
| Knob | Proposed start |
|---|---|
| X (max stealable / window) | `clamp(20% of current, min 5, max 50)` — flat X breaks at extremes |
| Shield max ("100%") | 16h |
| Shield duration | `(stolen ÷ X) × 16h`, min floor 4h |
| Shield burn while shielded | 15 min per hex captured (so a walk burns by how much it captures) |
| XP income | multiplier on actions (not idle trickle) |

### Open questions 🔵
- **O7 (critical) — newbie/veteran-farming + offline protection (replaces matchmaking):** tier-gated stealing? starter shield? both? (rec: both)
- **O2 — shield numbers:** confirm X as clamped %; shield max + floor; exact trigger timing of the auto-shield.
- **O6 — shield-burn numbers:** confirm per-hex burn vs per-walk %.
- **O8 — XP income:** multiplier on walks vs passive idle trickle. (rec: multiplier)
- **O3 — curves (after above):** current-hex → division thresholds (raise ceiling past 7k); XP → Level → cosmetic-unlock map.
- **O5 — XP cosmetic scope:** which of {hex skins, trail effects, claim animation, profile cosmetics, map theme, level-gated clan creation}.
- **O4 — fix seed data** to match final curves.

---

## 02 — Clans  ⚪ not started
(Depends on D3 — clan contribution consumes Current hexes.)

## 03 — Territory wars  ⚪ not started
## 04 — XP economy & cosmetic unlocks  ⚪ not started (depends on D6/O5)
