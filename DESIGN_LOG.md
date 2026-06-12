# 🌍 MyLoop — Game Design (Living Doc)

> Walk the real world, capture hexagon territory, rise solo and with your clan.
> _Working mode: **local only — not pushed.** Status: ✅ locked · 🔵 open · ⏳ deferred._

---

## 🗺️ The world in one picture

```mermaid
flowchart TD
    You((YOU)) -->|walk real streets| Solo[🟢 SOLO MAP<br/>your territory · stealable · shield · decay]
    You -->|opt-in, 6h, same-tier| Duel[⚔️ DUEL MAP<br/>1v1 · resets each time · safe]
    You -->|clan war, 5+ members| War[🏴 WAR MAP<br/>clan vs clan · resets · safe]

    Solo --> Hex[💎 HEXES<br/>territory · leaderboard · clan strength · XP income]
    Duel --> Tro[🏆 INDIVIDUAL TROPHIES<br/>→ your division]
    War --> CT[🛡️ CLAN TROPHIES<br/>→ clan division]
    You --> XP[✨ XP → cosmetics only]

    Duel -.net-new hexes.-> Solo
    War -.net-new hexes.-> Solo
```

**Three maps, three rewards.** Your Solo map is the only place hexes are real and stealable. Duels and Wars are temporary scoreboards on the same streets — safe, reset every time — and anything genuinely new you grab there flows back into Solo.

---

## 📖 How it all fits — Maya's story

**Day 1 — First steps (Stockholm).** Maya installs, picks an avatar + color, sets her home. A guided walk turns her first hexes green in real time; she curves back to her start and the whole block fills at once.
▸ _She now has **Hexes** (her territory), earned **XP**, and sits in the **Bronze** division._

**Day 2 — The world bites back.** A daily mission and her new streak pull her out again. While she's at work, a neighbor walks her block and steals 5 hexes — but her **shield** caps the bleed and buys her recovery time. That evening a push warns some hexes are about to **decay**; she re-walks to refresh them.
▸ _Solo map = **open + shield + decay**. Territory must be defended and maintained._

**Day 4 — Her first Duel.** Maya opts into a **Duel**: matched with a same-tier player, 6 hours, a **fresh map that starts at zero**. She doesn't grind — she plans one efficient **loop** (big interior for few steps), detours for a **5× bonus hex**, and watches her rival's **live bar** creep up. She wins by 12.
▸ _**+Individual Trophies** → climbing toward Silver. The brand-new land she grabbed is added to her **Solo** map (with decay). Her duel score didn't touch her account hex total — only the net-new did._

**Week 2 — She joins a clan.** Maya joins a clan (max **50** members) as a **Scout**. Her hex count now adds to **clan strength**. She chats with members to plan walks.
▸ _Solo hexes now do double duty: personal territory **and** clan power._

**Week 3 — Clan war.** The clan has 5+ members, so the **Captain** declares a **War** — same rules as a duel, but clan vs clan. Every member walks and collects on the reset war map (independent capture — no one blocks anyone). The clan out-collects the rival and wins.
▸ _**+Clan Trophies** → clan division rises. Maya personally banked **XP + net-new hexes**, but her **individual** trophies were untouched — wars and duels are separate ladders._

**Month 2 — Two ladders, climbing apart.** Maya is promoted to **Ranger** (she can invite now). She grinds duels to **Gold** individually, while the clan climbs its **own** division through wars. A weak dueler in her clan is still a war hero — different strengths, different ladders.

---

## 🧱 Reference

### 💠 The three things you earn
| Thing | Its one job | Earned from |
|---|---|---|
| **Hexes** (account) | Territory → map, leaderboard, clan strength, XP income | Solo collect; net-new in duels/wars |
| **Individual Trophies** | Your division + duel matchmaking | Duels: win **+**, lose **−** |
| **XP / Level** | Cosmetics only (never power) | All activity |

### 🗺️ The three maps
| Map | Stealable? | Shield? | Decay? | Persists? |
|---|---|---|---|---|
| 🟢 **Solo** | Yes (neighbors) | **Yes** | Yes | Yes — real territory |
| ⚔️ **Duel** | No | No | Resets each duel | Only **net-new** → Solo |
| 🏴 **War** | No | No | Resets each war | Only **net-new** → Solo |

_Net-new = a hex **that player** never owned before._

### 🎮 Modes → what they affect
| Mode | How it works | Affects |
|---|---|---|
| **Solo collect** | Walk real world; take neutral/decayed land; keep it (only decay removes it) | +Hexes, +XP, exploration, missions, streak |
| **Duel** | Opt-in, same-tier, 6h, fresh 0-start map; independent capture; live opponent bar | ±Individual Trophies → division, +XP, +net-new Hexes |
| **War** | Clan vs clan, needs **5+** members; otherwise = team duel | ±Clan Trophies → clan division, +XP & +net-new Hexes per member |

### 🧠 Strategy levers (duels **and** wars)
| Lever | Decision it adds | Built? |
|---|---|---|
| **Loops score big** | Plan a smart loop (interior fill) > raw steps | ✅ exists |
| **Bonus hexes (5×)** | Detour for the gold hex, or sweep cheap ones? | new, easy |
| **Best-of-3 objectives** | most hexes / biggest loop / most net-new → comebacks | ⏳ defer past v1 |

### 👥 Clans
- **Max 50 members.** War needs **≥5**. Chat = **clan-only** (trash-talk to opponents → v2).
- **Clan strength = Σ members' current hex count** → drives the clan leaderboard.
- **Roles** (Scout → Ranger → Captain → Sovereign):

| Role | Can do |
|---|---|
| 👑 **Sovereign** (leader) | Everything; promote/demote anyone; transfer leadership; disband |
| ⭐ **Captain** (co-leader) | Declare & manage wars; kick and promote up to Ranger |
| 🎖️ **Ranger** (elder) | Invite players; accept join requests |
| 🚶 **Scout** (member) | Walk, contribute hexes, chat |

### 🪜 Two separate ladders
| | **Individual** | **Clan** |
|---|---|---|
| Fueled by | Duels (win/lose) | Wars (win/lose) |
| Currency | Individual Trophies | Clan Trophies |
| Ladder | Your division (Bronze→Diamond) | Clan division |
| Matchmaking | Same individual tier | Same clan division |

---

## 📌 Status
| Entry | State |
|---|---|
| 01 Player progression spine | ✅ model locked |
| 02 Clans | ✅ locked (roles, 50 cap, war≥5, chat v1) |
| 03 Territory wars | ✅ model locked (v1 = sum of effort; contiguity → v2) |
| 04 XP cosmetics | 🔵 scope: hex skins, trail FX, claim FX, profile, map theme, level-gated clan-create |

## 🚀 Launch
**Single city: Stockholm.** Every multiplayer system (duels, wars, clans, stealing, leaderboards) needs local density; scattered global = empty map. Note: Turf (Sweden) proves the appetite and is the direct competitor.

## ⏳ Deferred tuning (numbers, after model)
Shield: X = clamp(% of holdings) + max/floor hours + burn-per-capture · Curves: Hex→division thresholds (raise past 7k), XP→Level · Seed-data fix.
