# 🌍 MyLoop — Game Design Foundation

> **Walk the real world. Capture hexagon territory. Rise solo, and conquer with your clan.**
> This doc is the single source of truth — readable as a story for customers, precise enough to build from.
> _Mode: local only, not pushed. Status: ✅ locked · 🔵 open._

---

## 🗺️ The world in one picture

```mermaid
flowchart TD
    You((YOU)) -->|walk real streets| Solo[🟢 SOLO<br/>your territory · stealable · shield · decay]
    You -->|opt-in 6h, same tier| Duel[⚔️ DUEL 1v1<br/>resets each time · safe]
    You -->|clan war, 5–50| War[🏴 CLAN WAR<br/>clan vs clan · resets · safe]

    Solo --> Hex[💎 HEXES]
    Duel --> Tro[🏆 TROPHIES]
    War --> CT[🛡️ CLAN TROPHIES]
    You --> XP[✨ XP]

    Hex --> HU[map territory · leaderboard · clan strength]
    Tro --> TU[your Tier + Division]
    CT --> CU[clan division]
    XP --> XU[cosmetic unlocks]

    Duel -.net-new hexes.-> Solo
    War -.net-new hexes.-> Solo
```

---

## 📖 Maya's story (how every piece connects)

**Day 1 — First territory.** Maya installs in Stockholm, picks an avatar + colour, sets her home. A guided walk turns hexes green in real time; she loops back to her start and the whole block fills.
▸ _She owns **Hexes**, earned **XP**, sits at **Bronze I**. A **starter shield** protects her for her first days._

**Day 2 — Defend & maintain.** A neighbour walks her block and steals a few hexes — her **shield** caps the loss and gives recovery time. A push warns hexes will **decay** tonight; she re-walks to refresh.
▸ _Solo = **open world + shield + decay**. Territory is held, not just collected._

**Day 4 — First Duel.** She opts into a **Duel**: matched with a same-**Tier** player, 6 hours, a **fresh map starting at zero**. She plans an efficient **loop**, grabs a **5× bonus hex**, and watches her rival's **live bar** climb. Wins by 12.
▸ _**+30 Trophies** → climbing toward Silver. The brand-new land she grabbed flows into her **Solo** map. Her hex *total* only grew from the net-new — re-walking her own land just scored duel points._

**Week 2 — A clan.** She joins a clan (max **50**) as a **Scout**. Her hexes now add to **clan strength**.
▸ _Her territory does double duty: personal + clan power._

**Week 3 — Clan War.** With 5+ members, the **Captain** declares **War** (24h). Everyone walks and collects on the reset war map. The clan out-collects the rival.
▸ _**+Clan Trophies** → clan division rises. Maya personally banked **XP + net-new hexes** — but her **individual Trophies were untouched.**_

**Month 2 — Two ladders.** Promoted to **Ranger** (can invite). She climbs duels to **Gold**; the clan climbs its **own** division through wars. A weak dueller can still be a war hero.

---

## 💰 The three things you earn — and what each is FOR

| | 💎 **Hexes** | 🏆 **Trophies** | ✨ **XP** |
|---|---|---|---|
| **What it is** | Land you hold right now | Your skill rating | Lifetime progress |
| **Earn by** | Solo collecting; net-new in duels/wars | Duels: win **+30**, lose **−15** | Every action (capture, walk, steal, missions, streak) |
| **Can it drop?** | Yes — stolen (shield protects) + decay | Yes — lose a duel (tier-floor protected) | No — only rises |
| **What it drives** | Map territory · **Leaderboard** · **Clan strength** | Your **Tier + Division** (Bronze→Diamond, I–IV) · duel matchmaking | **Levels → cosmetic unlocks** (+ clan-create gate) |
| **What it helps you achieve** | Be #1 by territory; power your clan | Prove you're the best player; climb leagues | Personalize your look; flex status |

_(Clans have a parallel **Clan Trophies → Clan Division** ladder, fed by wars.)_

### 🎖️ What climbing Tiers & Divisions gives you
- **v1:** status everywhere (profile, leaderboard, clan roster) **+ a tier-exclusive cosmetic** each new tier (Gold skin, Diamond trail) — wearable status, no power.
- **v2:** **Seasons** — monthly soft-reset + exclusive seasonal cosmetics by peak tier (the CoC/Apex recurring chase).
- _Hexes rank you by **territory** (leaderboard); Trophies rank you by **duel skill** (Tier). Two identities, both "winning."_

---

## 🎮 Solo vs Duel vs Clan War — side by side

| | 🟢 **Solo (you)** | ⚔️ **Duel (1v1)** | 🏴 **Clan War (team)** |
|---|---|---|---|
| **What you do** | Walk, claim neutral/decayed land, defend yours | Opt-in 6h race vs a same-Tier player | Team (5–50) races a rival clan, 24h |
| **The map** | Persistent real world | Fresh 0-start overlay | Fresh 0-start overlay |
| **Stealable?** | Yes (shield protects) | No | No |
| **You earn** | Hexes, XP, missions, streak | ±Trophies, XP, net-new hexes | +XP, net-new hexes |
| **Affects YOU** | Hexes → leaderboard, clan strength | **Trophies → your Tier/Division** | XP + hexes only — **your Tier untouched** |
| **Affects CLAN** | Your hexes = clan strength | — | **Clan Trophies → clan division** |
| **Win condition** | (ongoing) | Higher score in 6h | Clan with higher total |

---

## 🔁 How wins & losses ripple

```mermaid
flowchart LR
    DW[Win duel] -->|+30| T[Your Trophies] --> Tier[Your Tier + Division ↑]
    DL[Lose duel] -->|−15| T
    WW[Clan wins war] -->|+| CTr[Clan Trophies] --> CD[Clan Division ↑]
    WL[Clan loses war] -->|−| CTr
    War[War, either result] -->|+XP, +net-new hexes| Me[You personally]
```

**Key rule:** duels are *your* ladder; wars are the *clan's* ladder. Helping your clan win a war never moves your personal Tier — but it grows your hexes, your XP, and your clan's standing.

---

## 🧠 How to win — strategy (duels **and** wars)

| Lever | The decision it creates | Built? |
|---|---|---|
| **Loops score big** | Close a loop → capture the whole interior. Smart routing beats raw steps. | ✅ exists |
| **Bonus hexes (5×)** | 3–5 high-value hexes appear; detour for them or sweep cheap land? | new |
| **Live opponent bar** | You see them gaining → push harder, time your final loop | new |
| **Best-of-3 objectives** | most hexes / biggest loop / most net-new → comeback paths | 🔵 v2 |
| **Clan coordination** | (wars) members link territory for a bonus | 🔵 v2 (needs density) |

---

## 👥 Clans

- **Max 50 members.** War needs **≥5**. Chat = **clan-only** (trash-talk to rivals → v2).
- **Clan strength = Σ members' current hex count** → clan leaderboard.
- **Clan discovery:** browse/search clans (sorted by division, activity, proximity) + request to join — so new players actually find a clan.
- High clan division → **cosmetic clan badge + bragging rights** (v1); perks (bigger cap, etc.) → v2.
- **Roles** (Scout → Ranger → Captain → Sovereign):

| Role | Can do |
|---|---|
| 👑 **Sovereign** (leader) | Everything; promote/demote anyone; transfer leadership; disband |
| ⭐ **Captain** (co-leader) | Declare & manage wars; kick and promote up to Ranger |
| 🎖️ **Ranger** (elder) | Invite players; accept join requests |
| 🚶 **Scout** (member) | Walk, contribute hexes, chat |

---

## 🔢 Numbers — v1 starting values (tune with live data)

**🛡️ Solo defense** — per-hex cooldown **6h** · steal cap per window **clamp(20% of holdings, 5–50)** · shield **(stolen÷X)×16h, min 4h** · shield burns **−20 min per hex you capture while shielded** · **starter shield 3 days / until 50 hexes** · decay 7d local→90d far.

**🏆 Trophy → Tier** — Bronze 0 · Silver 400 · Gold 1,000 · Platinum 1,800 · Crystal 2,800 · Diamond 4,000 (each = 4 divisions). Duel **win +30 / lose −15**, tier-floor protected. Matchmaking ±150 trophies. First 3 duels = placement.

**✨ XP & Levels** — `Level = 1 + √(XP/100)`. Capture +10 · steal +25 · walk +50/km · streak +20/day · all-missions +100 · achievements +25–1000. _(XP from actions only — no idle/territory income.)_

**🎨 Cosmetic unlocks** — L1 base skin+trail · L3 skin#2 · **L5 clan creation** + trail FX · L8 claim FX · L10 profile frame · L15 map theme · L20 premium skin · + seasonal drops from duel/war wins.

**⚔️ Duel / War** — Duel: **queue & search → push when matched → both get 6h**; **ghost-duel fallback** (race a same-tier player's recorded run) if no match in ~2 min. 3/day, same-division. War 24h, 5–50, same clan division. Bonus hexes 3–5 @ 5×.

**⚙️ Code constants (`GameConstants.cs`)** — `CellCooldownHours 0.0167→6.0` · rename/retire `HexTier` → trophy-driven `Tier` · add `ShieldMaxHours=16, ShieldFloorHours=4, StealCapPct=0.2(min5/max50), StarterShieldDays=3, ShieldBurnMinPerHex=20, TrophyWin=30, TrophyLoss=15` + division floors · fix seed users.

---

## 📌 Status & Launch
01 Progression ✅ · 02 Clans ✅ · 03 Wars ✅ · 04 Cosmetics ✅ · 05 Numbers ✅ (tune live).
**Launch single-city: Stockholm** — all multiplayer needs local density; scattered = empty map. (Turf = proven appetite + competitor.)

---

## ✅ Decisions locked this round
- Duel matching = **queue & search → push when matched → both 6h**, with **ghost-duel fallback** (recorded same-tier run) so duels always fire at launch.
- **Tier rewards** = status + tier-exclusive cosmetics (v1); **Seasons** (v2).
- **Clan division** = cosmetic clan badge + bragging (v1); perks (v2). **Clan discovery browser** added.
- `HexTier` → **Tier** (trophy-driven). **XP-income removed.**

## 🔵 Known issue to tune (not a blocker)
- **Duel fairness vs geography:** matched by skill, but a walking race also favours dense areas + free time. Loops + bonus hexes give an efficiency path. v1: accept; if telemetry shows geography dominating, switch duel scoring to **hexes-per-km**.

## ⏳ v2 backlog
Seasons · clan missions (keep clans alive between wars) · best-of-3 duel objectives · clan contiguity bonus · trash-talk chat · clan perks.
