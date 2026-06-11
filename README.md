Here is your fully clean, unified, and hyper-structured `README.md`.

Following your non-negotiable instruction, **all content, paths, stack updates, and architectural constraints introduced after June 11, 2026, have been used as the source of truth.** Any older contradictions (such as the old database indexing methods, outdated folders, and missing architectural design requirements) have been systematically purged and updated.

---

# MyLoop 🌍⬡

**Real-world territory capture.** Walk a loop in the physical world → claim every hex inside it. Defend your territory. Steal from others. Dominate your city's leaderboard.

> Pokémon GO meets Risk meets Strava — but you're conquering real geographic territory.

---

## How It Works

```
1. Open app → see the hex map with everyone's territory
2. Tap START JOURNEY → walk outside
3. Walk a closed loop → GPS traces your path
4. Tap STOP & CAPTURE → server validates your walk
5. Every hex inside your loop becomes YOURS (colored on the map)
6. Other players get push notifications: "Your territory was stolen!"
7. They walk back to reclaim → the cycle continues

```

**Why it's addictive:** You *see* your territory on the map. Others can *steal* it. You get *notified* instantly. You *walk back* to defend. Repeat forever.

---

## Features

| Feature | Description |
| --- | --- |
| 🗺️ Territory Capture | Walk loops to claim H3 hexagonal cells. Trail + interior fill. |
| ⚡ Real-Time Updates | SignalR WebSocket pushes map changes to all nearby players instantly. |
| 🛡️ Anti-Cheat | 3-layer validation: speed, duration, path smoothness. |
| 🔔 Push Notifications | FCM alerts when your territory is stolen. |
| 🏆 Leaderboard | City / Country / World scoped rankings, refreshed daily. |
| 🎖️ Tier System | Bronze → Silver → Gold → Platinum → Crystal → Diamond (24 ranks). |
| 🔥 Streaks | Daily consecutive claim tracking with lifetime max. |
| ⚔️ Revenge | See who stole from you + navigate back to reclaim. |
| 📜 Walk History | Paginated record of all past claims. |
| 👤 Profiles | Public player profiles with titles, badges, stats. |
| 🤖 Bot Territory | Pre-seeded competition in 6 major cities. |
| 🗓️ Cooldown & Decay | 5-hour protection on captured cells; cell decay over a default of 7 days. |

---

## Tech Stack

| Layer | Technology | Operational Specifics |
| --- | --- | --- |
| **Mobile** | Flutter 3.44 / Dart 3.12 | Core Framework (iOS + Android) |
| **State Engine** | Riverpod 3.x (Notifier) | Compile-safe Single Source of Truth (SSOT) |
| **Network Client** | Dio | HTTP REST Client with automated Bearer JWT interceptors |
| **Backend** | .NET 10 / ASP.NET Core | High-performance architecture, thin controllers |
| **Database** | PostgreSQL 18 | Relational engine utilizing advanced BRIN indexing |
| **Spatial Grid** | Uber H3 Engine | Resolution-11 cells (~4,234 m²/hex), uniform filling |
| **Real-Time** | SignalR (WebSocket) | `signalr_netcore` foreground geo-broadcasts & groups |
| **Auth** | Firebase Authentication | Google + Apple OAuth, validation via Firebase JWT |
| **Push** | Firebase Cloud Messaging | FCM HTTP v1 protocol background alert framework |
| **Map Tiles** | ESRI + CartoDB | Spatial tilesets (satellite + dark themes) |
| **Navigation** | go_router + ShellRoute | Explicit URL routing & tab state persistence |

---

## System Architecture

### Process Layout Blueprint

```
┌─────────────────────────────────────────────────────────┐
│  MOBILE (Flutter)                                       │
│  ┌──────────┐  ┌───────────┐  ┌──────────────────────┐ │
│  │ GPS      │  │ Map       │  │ SignalR Client        │ │
│  │ Tracking │  │ Rendering │  │ (region subscription) │ │
│  └────┬─────┘  └─────┬─────┘  └──────────┬───────────┘ │
│       │               │                    │             │
│       ▼               ▼                    ▼             │
│  ┌─────────────────────────────────────────────────┐    │
│  │          API Service (Dio + JWT interceptor)     │    │
│  └───────────────────────┬─────────────────────────┘    │
└──────────────────────────┼──────────────────────────────┘
                           │ HTTPS + WebSocket
┌──────────────────────────┼──────────────────────────────┐
│  BACKEND (.NET 10)       │                              │
│  ┌───────────────────────┴─────────────────────────┐    │
│  │           Controllers (thin, ≤20 lines)         │    │
│  └───────────────────────┬─────────────────────────┘    │
│                          │                              │
│  ┌───────────┬───────────┼───────────┬──────────────┐   │
│  │Territory  │PathValid  │HexGrid   │Leaderboard   │   │
│  │Service    │Service    │Service   │Service       │   │
│  │(claims)   │(anti-cheat)│(H3 math) │(rankings)   │   │
│  └─────┬─────┴─────┬─────┴────┬─────┴──────┬───────┘   │
│        │           │          │            │            │
│  ┌─────▼───────────▼──────────▼────────────▼────────┐   │
│  │       EF Core → PostgreSQL (BRIN spatial index)  │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  ┌─────────────────┐  ┌────────────────────────────┐    │
│  │ SignalR Hub      │  │ Push Notification Service  │    │
│  │ (region groups)  │  │ (FCM HTTP v1)              │    │
│  └─────────────────┘  └────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘

```

### End-to-End Data Lifecycle (8 Thresholds)

```
[A: UI Gesture / Stream Allocation] ──► [B: Riverpod Slice Mutation] ──► [C: Dio Serialization Engine]
                                                                                   │
                                                                                   ▼
[F: Service + H3 Spatial Math] ◄── [E: .NET Controller Binding] ◄── [D: REST / SignalR Boundary]
             │
             ▼
[G: EF Core TXN (Serializable)] ──► [H: SignalR/FCM Broadcast Update] ──► Back to [A/B State Graph]

```

### Communication Patterns

| Pattern | Tech | Direction | Purpose |
| --- | --- | --- | --- |
| REST | HTTP/JSON | Client → Server → Client | Claims, queries, profiles, missions, achievements |
| WebSocket | SignalR | Server → Clients | Foreground real-time territory updates |
| Push | FCM HTTP v1 | Server → Device OS → Client | "Your hex was stolen" background alerts |
| Auth | Firebase JWT | Client → Server (Bearer) | Cryptographic verification via `ICurrentUser` |
| Geo Groups | SignalR | Client ↔ Server | Dynamic subscription to ~12km regional streams |

---

## Core Algorithms

### Claim Pipeline

```
GPS Path (200m+ walk, ≥10 points)
    │
    ▼
┌─ Anti-Cheat Validation ──────────────────────┐
│  • Speed: ≤30 km/h between consecutive points │
│  • Duration: ≥50% expected GPS samples        │
│  • Smoothness: bearing σ > 2° (rejects bots)  │
└───────────────────────────────────────────────┘
    │
    ▼
┌─ H3 Hex Computation ─────────────────────────┐
│  1. Trail cells: hexes the path crosses       │
│  2. Loop detection: endpoints ≤50m apart      │
│  3. Polygon fill: H3.Fill() for interior      │
│  4. Deduplication: skip >80% overlap          │
└───────────────────────────────────────────────┘
    │
    ▼
┌─ Ownership Assignment (single DB transaction) ┐
│  • Skip cells on cooldown (5h protection)     │
│  • Skip self-owned cells                      │
│  • Steal from others → log transfer           │
│  • Update stats (hex count, streak, distance) │
└───────────────────────────────────────────────┘
    │
    ▼
┌─ Post-Commit Broadcast ──────────────────────┐
│  • SignalR → all nearby clients (map update)  │
│  • FCM → victims ("Territory Under Attack!")  │
└───────────────────────────────────────────────┘

```

### Anti-Cheat Specifications

| Check | Method | Threshold | Tolerance |
| --- | --- | --- | --- |
| Speed | Haversine calculation over adjacent coordinate elements | 60m per 5s interval (30 km/h) | 5% violation rate tolerated |
| Duration | Sample density vs expected footprint over path length | 50% of mathematically expected samples | Enforced strict threshold |
| Smoothness | Standard deviation ($\sigma$) of bearing trajectory | $\sigma > 2^\circ$ required | Blocks linear automated bots |

---

## Repository Layout

```
MyLoop/
├── mobile/                            # Flutter Application
│   └── lib/
│       ├── app/                       # Router (go_router), global themes, app shell
│       ├── features/                  # UI Domain Contexts
│       │   ├── journey/               # Active tracking loop, GPS engine, map rendering
│       │   ├── home/                  # Central layout dashboard, navigation layers
│       │   ├── leaderboard/           # Global, national, and urban user lists
│       │   ├── achievements/          # Milestones and trophies
│       │   ├── profile/               # User core parameters & details
│       │   ├── history/               # Paginated records of processed walks
│       │   └── auth/                  # Credentials interface
│       └── shared/
│           ├── state/                 # SSOT State Slices (profile, xp, missions, etc.)
│           ├── services/              # External interfaces (api_service, batch_drain_service)
│           └── models/                # Typed data payloads (territory_cell, user)
│
└── api/                               # .NET 10 Web API Backend
    └── MyLoop.Api/
        ├── Controllers/               # Claims, Territory, Missions, Achievements, Users
        ├── Services/                  # Core Systems (Territory, Mission, HexGrid, Achievement)
        ├── Hubs/                      # SignalR TerritoryHub (Spatial & Individual Groups)
        ├── Entities/                  # Entity Framework Core relational domain mappings
        ├── Data/                      # AppDbContext schema context & structural boundaries
        └── Program.cs                 # App entrypoint, DI configurations, security bootstrap

```

---

## API Endpoints

### Territory (`/api/territories`)

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `GET` | `/api/territories?minLat&minLng&maxLat&maxLng` | Viewport bounding box query (max 500) |
| `GET` | `/api/territories/user/{userId}` | Complete unpaginated user cell array |
| `GET` | `/api/territories/stats/{userId}` | Comprehensive cell counts + aggregate area metric |
| `GET` | `/api/territories/stolen/{userId}?days=7` | Historically processed thefts targeting user |
| `GET` | `/api/territories/history/{cellId}` | Audited historic transitions of specific H3 cell |
| `GET` | `/api/territories/claims/{userId}` | Historically processed walk records |

### Claims (`/api/claims`)

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `POST` | `/api/claims` | Submit processing pipeline for verification |
| `POST` | `/api/claims/preview` | Client UI map visual preview trace (No DB persistence) |

### Users (`/api/users`)

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `POST` | `/api/users/register` | Create account |
| `GET` | `/api/users/{id}` | Target specific player details |
| `GET` | `/api/users/by-uid/{firebaseUid}` | Gateway lookup resolving Firebase Unique ID |
| `PATCH` | `/api/users/{id}` | Mutate client properties |
| `GET` | `/api/users/{id}/profile` | Exposed profile metadata + calculated tier |
| `DELETE` | `/api/users/{id}` | Atomic GDPR wipe request |
| `POST` | `/api/users/{id}/device-token` | Append target registration string for FCM routines |
| `GET` | `/api/users/{id}/claims?page&pageSize` | Paginated index array of past claims |

### Missions & Leaderboards (`/api/missions`, `/api/leaderboard`)

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `GET` | `/api/leaderboard?scope=city&lat&lng` | Spatial geographic metrics rankings |
| `POST` | `/api/leaderboard/refresh` | Force target generation script for daily rankings |

---

## Database Schema & Indexes

| Table | Primary Key | Purpose |
| --- | --- | --- |
| `Users` | UUID | Core entity tracking player identity, statistics, and streaks |
| `TerritoryCells` | H3 CellId (bigint) | Hex boundaries mapping, live ownership state, and cooldowns |
| `Claims` | UUID | Immutable collection containing route metrics, points, and target size |
| `CellTransfers` | UUID | Log entries for tracking thefts and configuring revenge options |
| `LeaderboardEntries` | UUID | Aggregated historical daily spatial score snapshots |
| `DeviceTokens` | UUID | Registry linking active platform messaging references |

### Production Spatial Optimizations

These indexes must be configured in your environment to ensure performant spatial operations under heavy concurrent traffic:

```sql
-- High-speed block-range spatial tracking matching coordinates criteria
CREATE INDEX IF NOT EXISTS "IX_TerritoryCells_Geo_Brin"
  ON "TerritoryCells" USING BRIN ("CenterLat", "CenterLng") WITH (pages_per_range=128);

-- Query acceleration for aging decay processes
CREATE INDEX IF NOT EXISTS "IX_TerritoryCells_Decay"
  ON "TerritoryCells" ("LastRefreshedAt", "DecayDays");

-- Keystone idempotency protection enforcing clean uniqueness boundaries on structural resets
CREATE UNIQUE INDEX IF NOT EXISTS "UX_DailyMissions_User_Date_Type"
  ON "DailyMissions" ("UserId", "Date", "Type");

```

---

## System Progression & Environment Balance

### Tier Badges (24 Ranks)

| Tier | Hex Threshold | Identity Color |
| --- | --- | --- |
| 🥉 Bronze I–IV | 0 – 49 | `#CD7F32` |
| 🥈 Silver I–IV | 50 – 199 | `#A8B4C0` |
| 🥇 Gold I–IV | 200 – 499 | `#FFD700` |
| 💎 Platinum I–IV | 500 – 1,499 | `#8B5CF6` |
| 💠 Crystal I–IV | 1,500 – 2,999 | `#00BCD4` |
| 🔷 Diamond I–IV | 3,000+ | `#60A5FA` |

### Player Titles

* **Drifter:** 0+ cells
* **Wanderer:** 10+ cells
* **Trailblazer:** 50+ cells
* **Territory Lord:** 100+ cells
* **Hex Overlord:** 500+ cells
* **Grid Dominator:** 1,000+ cells

### Non-Negotiable Game Constants

* **Spatial Unit Resolution:** Uber H3 Res-11 ($~4,234\text{ m}^2$ area per hexagon).
* **Maximum Daily Threshold:** 20 claims maximum per user per day.
* **Cooldown Buffer:** 5-hour strict protection window preventing immediate territory counters.
* **Decay Matrix:** 7 days default window before unmaintained cell ownership deterioration activates.
* **Loop Enclosure Variance:** $\le 50\text{ m}$ maximum separation permitted between initial and final route coordinates.

---

## Brand Theme Directory

| Asset Component | Hex Code | Purpose |
| --- | --- | --- |
| **Electric Turquoise** | `#00D4AA` | Core signature palette baseline color |
| **Deep Turquoise** | `#00B894` | Primary element contrast shadow accent |
| **Mint Frost** | `#E0FFF7` | Base overlay panel background component |
| **Royal Purple** | `#6C5CE7` | Interactive control accent / highlighting element |

---

## Execution & Deployment

### Backend Setup

1. Move to the directory context:
```bash
cd api/MyLoop.Api

```


2. Establish your infrastructure configurations tracking your localized database parameters:
```bash
cp appsettings.Development.example.json appsettings.Development.json

```


3. Boot the environment. Database structures automatically map schemas on initialization via `EnsureCreated` and underlying idempotent Data Definition Language scripts:
```bash
dotnet run

```



* **API Context Base URL:** `http://localhost:5000/`
* **SignalR WebSocket Entry Point:** `http://localhost:5000/hubs/territory`

### Mobile App Deployment

1. Initialize missing dependencies:
```bash
cd mobile && flutter pub get

```


2. Execute target runtime profile passing the backend initialization parameters explicitly:
```bash
flutter run --dart-define=API_BASE_URL=http://localhost:5000

```



### Operational Infrastructure Proxy Prototyping (Real-World GPS Deployment)

To stream local backend context out safely to test tracking functionality on an actual physical testing handset, use an `ngrok` routing tunnel:

1. Connect the local proxy port structure:
```bash
ngrok http 5000

```


2. Compile your mobile environment pointing directly to the generated secure gateway proxy address:
```bash
flutter run --dart-define=API_BASE_URL=https://<your-assigned-id>.ngrok.app

```



> ⚠️ **CORS Directive Warning:** You must add the generated proxy root address domain to the target backend configurations under `Cors:AllowedOrigins` to prevent web browser profile compilation tasks from throwing security violations. Native compilation targets ignore CORS boundaries.

---

## Non-Negotiable Architectural Rules

Future modifications must comply entirely with these architectural constraints:

1. **Strict Single Source of Truth (SSOT):** There is exactly **one** store per structural domain context. Profile statistics, tracking telemetry, and count values live *strictly* within `profileSlice` and derived states. Under no circumstances should separate widgets or independent state notifiers maintain duplicated counts, caches, or independent states.
2. **Authoritative Server Control:** Every channel (HTTP REST responses, live WebSockets via SignalR, or incoming FCM background routines) funnels mutations directly into the exact same domain reducer slice. Server-sent payloads carry absolute, verified values; local calculations are strictly optimistic UI updates that roll back on server error.
3. **SignalR Connection Lifecycle Management:** The real-time connection stream is owned and controlled *exclusively* by the central auth state context. Connections must initialize on successful authentication and systematically dispose on teardown. Never bind connection lifecycles to individual feature screens or transient widgets.
4. **Leak Mitigation Cleanup Protocols:** Every feature widget utilizing streams, event loop handlers, animation parameters, or controllers must include an explicit cleanup wrapper within `dispose()` routine contexts to eliminate underlying component drift or memory leaks.
5. **Serialization Data Integrity Constraints:** H3 Cell Identifiers must cross network layers **exclusively as explicit string representations** across every transport pipe to prevent precision degradation when processing 64-bit numerical primitives on web layers.
6. **Idempotent Operations Rule:** All creation or modification endpoints must rely entirely on core structural **Unique Indexes** and explicit unique database constraints to prevent race conditions. Check-then-act logic patterns are strictly forbidden. Modifying core player data metrics require execution blocks within isolated database transactions locked using explicit user-level advisory locks.
7. **Identity Resolution:** The operational actor must be determined *strictly* using claims processed within the validated bearer Firebase JWT structure (`ICurrentUser`). Ignore identifiers passed manually inside the request body payload. SignalR group authorization logic must explicitly verify that the connector's verified parameters exactly match requested parameters before processing subscription requests.

---

## Project Status

* **Completed Functionality:**
* ✅ Territory capture pipeline (including closed-loop processing routines)
* ✅ SignalR high-performance real-time active map synchronizations
* ✅ Three-layer multi-point server anti-cheat engine
* ✅ Structured Firebase Cloud Messaging push system integrations
* ✅ Scoped leaderboard snapshots (City, Country, Global scopes)
* ✅ Achievement framework tracking and 24-rank progression badge mapping
* ✅ Fully paginated, low-overhead historical walk index records
* ✅ High-density automated competitive bot territory injection maps
* ✅ GDPR cascade deletion procedures


* **Open System Operations Pending Resolution:**
* 🔶 Complete credential setups on target platform consoles (Firebase OAuth setup)
* 🔶 Production-grade continuous integration pipeline assembly
* 🔶 Store submission structural assembly configurations



---

## License

Private repository. All rights reserved. Reproduction or deployment strictly forbidden without explicit authorization.
