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

**Why it's addictive:** You _see_ your territory on the map. Others can _steal_ it. You get _notified_ instantly. You _walk back_ to defend. Repeat forever.

---

## Features

| Feature | Description |
|---------|-------------|
| 🗺️ Territory Capture | Walk loops to claim H3 hexagonal cells. Trail + interior fill. |
| ⚡ Real-Time Updates | SignalR WebSocket pushes map changes to all nearby players instantly |
| 🛡️ Anti-Cheat | 3-layer validation: speed, duration, path smoothness |
| 🔔 Push Notifications | FCM alerts when your territory is stolen |
| 🏆 Leaderboard | City / Country / World scoped rankings, refreshed daily |
| 🎖️ Tier System | Bronze → Silver → Gold → Platinum → Crystal → Diamond (24 ranks) |
| 🔥 Streaks | Daily consecutive claim tracking with lifetime max |
| ⚔️ Revenge | See who stole from you + navigate back to reclaim |
| 📜 Walk History | Paginated record of all past claims |
| 👤 Profiles | Public player profiles with titles, badges, stats |
| 🤖 Bot Territory | Pre-seeded competition in 6 major cities |
| 🗓️ Cooldown | 5-hour protection on captured cells |

---

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| **Mobile** | Flutter 3.44 / Dart 3.12 | Single codebase iOS + Android |
| **Backend** | .NET 10 / ASP.NET Core | SignalR native, high perf, EF Core |
| **Database** | PostgreSQL 18 | GiST spatial index, free, reliable |
| **Spatial Grid** | H3 (Uber) — pocketken.H3 | Global uniform hexagons, polygon fill, hierarchy |
| **Real-Time** | SignalR (WebSocket) | Group-based geo broadcast, auto-reconnect |
| **Auth** | Firebase Authentication | Google + Apple OAuth, JWT tokens |
| **Push** | Firebase Cloud Messaging | Cross-platform, free at scale |
| **Map Tiles** | ESRI + CartoDB | Free, no API key, satellite + dark themes |
| **State** | Riverpod 3.x | Compile-safe reactive state |
| **Navigation** | go_router + ShellRoute | URL-based routing, tab persistence |

---

## Architecture

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
│  │       EF Core → PostgreSQL (GiST spatial)        │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  ┌─────────────────┐  ┌────────────────────────────┐    │
│  │ SignalR Hub      │  │ Push Notification Service  │    │
│  │ (region groups)  │  │ (FCM HTTP v1)              │    │
│  └─────────────────┘  └────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### Communication Patterns

| Pattern | Tech | Direction | Purpose |
|---------|------|-----------|---------|
| REST | HTTP/JSON | Client → Server → Client | Claims, queries, profiles |
| WebSocket | SignalR | Server → Clients | Real-time territory changes |
| Push | FCM | Server → Device OS → Client | "Your hex was stolen" (app closed) |
| Auth | Firebase JWT | Client → Server (Bearer) | Every API call, auto-refresh |
| Geo Groups | SignalR | Client ↔ Server | Subscribe to ~12km region broadcasts |

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

### Anti-Cheat (3-Layer)

| Check | Method | Threshold | Tolerance |
|-------|--------|-----------|-----------|
| Speed | Haversine between consecutive points | 60m per 5s interval (30 km/h) | 5% violation rate allowed |
| Duration | Point count vs expected for distance | 50% of expected GPS samples | — |
| Smoothness | Std deviation of bearing changes | >2° required | Rejects linear spoofed paths |

---

## Project Structure

```
MyLoop/
├── mobile/                          # Flutter app (iOS + Android)
│   └── lib/
│       ├── app/                     # Theme, router, providers
│       ├── features/
│       │   ├── auth/                # Login, signup, avatar picker
│       │   ├── home/                # Main tab (map overview, stats, challenges)
│       │   ├── journey/             # Active walk (GPS tracking, hex rendering)
│       │   ├── history/             # Walk history (paginated claims)
│       │   ├── leaderboard/         # Rankings (city/country/world)
│       │   └── profile/             # User profile & settings
│       └── shared/
│           ├── constants/           # App-wide constants
│           ├── models/              # DTOs (TerritoryCell, AppUser, etc.)
│           ├── services/            # API, auth, location, push, SignalR
│           └── widgets/             # Reusable UI components
│
├── api/                             # .NET 10 backend
│   └── MyLoop.Api/
│       ├── Constants/               # GameConstants, AntiCheatConstants
│       ├── Controllers/             # Thin REST controllers
│       ├── Data/                    # EF Core DbContext + migrations
│       ├── Entities/                # DB models (User, TerritoryCell, Claim, etc.)
│       ├── Hubs/                    # SignalR TerritoryHub
│       ├── Models/                  # Request/response DTOs
│       ├── Services/                # Business logic (9 services)
│       └── Program.cs              # DI, auth, CORS, middleware, seeding
│
└── README.md
```

---

## API Endpoints

### Territory (`/api/territories`)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| `GET` | `/api/territories?minLat&minLng&maxLat&maxLng` | Viewport hex query (max 500) |
| `GET` | `/api/territories/user/{userId}` | All user's hexes (no limit) |
| `GET` | `/api/territories/stats/{userId}` | Cell count + area |
| `GET` | `/api/territories/stolen/{userId}?days=7` | Hexes stolen from user |
| `GET` | `/api/territories/history/{cellId}` | Ownership history of a cell |
| `GET` | `/api/territories/claims/{userId}` | Walk history |

### Claims (`/api/claims`)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| `POST` | `/api/claims` | Submit territory claim |
| `POST` | `/api/claims/preview` | Preview capture (no DB write) |

### Users (`/api/users`)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| `POST` | `/api/users/register` | Create account |
| `GET` | `/api/users/{id}` | Get user |
| `GET` | `/api/users/by-uid/{firebaseUid}` | Lookup by Firebase UID |
| `PATCH` | `/api/users/{id}` | Update profile |
| `GET` | `/api/users/{id}/profile` | Public profile + rank |
| `DELETE` | `/api/users/{id}` | Delete account (GDPR) |
| `POST` | `/api/users/{id}/device-token` | Register FCM token |
| `GET` | `/api/users/{id}/claims?page&pageSize` | Paginated claim history |

### Leaderboard (`/api/leaderboard`)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| `GET` | `/api/leaderboard?scope=city&lat&lng` | Rankings (city/country/world) |
| `POST` | `/api/leaderboard/refresh` | Recompute daily rankings |

---

## Database Schema

| Table | Primary Key | Purpose |
|-------|-------------|---------|
| `Users` | UUID | Player accounts, stats, streaks |
| `TerritoryCells` | H3 CellId (bigint) | Hex ownership, boundaries, cooldowns |
| `Claims` | UUID | Walk records (GPS path, cell count, area) |
| `CellTransfers` | UUID | Ownership change history (revenge feature) |
| `LeaderboardEntries` | UUID | Daily rank snapshots |
| `DeviceTokens` | UUID | FCM push notification tokens |

**Indexes**: GiST on `(CenterLat, CenterLng)` for spatial viewport queries. B-tree on `OwnerId`, `ParentCellId`, `FirebaseUid`.

---

## Game Constants

| Rule | Value |
|------|-------|
| Hex size (H3 res 11) | ~25m edge, ~2,150 m² area |
| Min walk distance | 200m |
| Max claim area | 5 km² |
| Claims per day | 20 max |
| Cell cooldown | 5 hours |
| Loop closure | ≤50m between path endpoints |
| Anti-cheat speed cap | 30 km/h |
| Viewport cell limit | 500 per request |
| Leaderboard scope | City / Country / World |
| Revenge window | 7 days |

---

## Running Locally

### Prerequisites

- [Flutter SDK](https://flutter.dev) ≥ 3.44.0
- [.NET 10 SDK](https://dotnet.microsoft.com)
- [PostgreSQL 18](https://postgresql.org)
- Firebase project (for auth + push)

### Backend

```powershell
cd api/MyLoop.Api
dotnet run --urls "http://0.0.0.0:5048"
# API at http://localhost:5048
# SignalR Hub at http://localhost:5048/hubs/territory
```

The API auto-creates the database and seeds bot territory on first run.

### Mobile (iOS/Android device)

```powershell
cd mobile
flutter run
```

### Mobile (Web — dev only)

```powershell
cd mobile
flutter build web --release
# Serve with any static server on port 9090
```

### Remote Testing (ngrok)

```powershell
ngrok http 5048
# Copy the https://xxx.ngrok-free.app URL
# Update api_service.dart apiBaseUrl or use --dart-define=API_URL=...
```

---

## Security

| Layer | Implementation |
|-------|---------------|
| Auth | Firebase JWT (RSA signature, issuer/audience validation) |
| Anti-Cheat | Speed + duration + smoothness checks server-side |
| Injection | Parameterized queries only (EF Core) |
| Rate Limiting | 20 claims/day (server-enforced) |
| Cooldown | 5-hour server-enforced, client cannot bypass |
| Data Deletion | Full GDPR cascade delete |
| Transport | HTTPS enforced |

---

## Progression System

### Tier Badges (24 ranks)

| Tier | Hexes | Color |
|------|-------|-------|
| 🥉 Bronze I–IV | 0 – 49 | `#CD7F32` |
| 🥈 Silver I–IV | 50 – 199 | `#A8B4C0` |
| 🥇 Gold I–IV | 200 – 499 | `#FFD700` |
| 💎 Platinum I–IV | 500 – 1,499 | `#8B5CF6` |
| 💠 Crystal I–IV | 1,500 – 2,999 | `#00BCD4` |
| 🔷 Diamond I–IV | 3,000+ | `#60A5FA` |

### Player Titles

| Title | Hex Threshold |
|-------|--------------|
| Drifter | 0+ |
| Wanderer | 10+ |
| Trailblazer | 50+ |
| Territory Lord | 100+ |
| Hex Overlord | 500+ |
| Grid Dominator | 1,000+ |

---

## Color Palette

| Color | Hex | Usage |
|-------|-----|-------|
| Electric Turquoise | `#00D4AA` | Primary brand |
| Deep Turquoise | `#00B894` | Primary dark |
| Mint Frost | `#E0FFF7` | Light backgrounds |
| Royal Purple | `#6C5CE7` | Accent / highlights |

---

## Cost to Run

| Phase | Monthly Cost |
|-------|-------------|
| Development (current) | **$0** — all services free tier |
| Production (0–10K users) | **~$25–75** — managed Postgres + Railway/Fly.io |
| Scale (10K–100K users) | **~$150–500** — larger DB, Redis cache, CDN |

---

## Status

- ✅ Territory capture (full pipeline)
- ✅ Real-time SignalR updates
- ✅ Anti-cheat validation
- ✅ Push notifications
- ✅ Leaderboard (city/country/world)
- ✅ Achievements & tier system
- ✅ Walk history
- ✅ Bot territory seeding
- ✅ Account deletion (GDPR)
- 🔶 Firebase OAuth credentials (needs console setup)
- 🔶 Production hosting
- 🔶 App Store submission

---As of June 11, 2026---

▎ Presented inline (your existing README.md is tracked — I won't overwrite it without your go-ahead).

# MyLoop — Real-Time Territory-Capture Walking Game

A spatial multiplayer game: walk closed loops to capture H3 hexagons, steal rivals'
territory by walking through it, climb city/country/world leaderboards.

## Stack
| Layer | Tech |
|---|---|
| Mobile | Flutter 3.44 · Riverpod 3.x (Notifier) · Dio · signalr_netcore · geolocator |
| API | .NET 10 · ASP.NET Core · EF Core (Npgsql) · SignalR · Firebase JWT auth |
| Data | PostgreSQL 18 · H3 res-11 cells · BRIN geo index · Nominatim geocoding |
| Push | SignalR (foreground real-time) · FCM HTTP v1 (background) |

## Repository Layout
mobile/lib/
  app/            router, theme, app shell
  features/       journey · home · leaderboard · achievements · profile · history · auth
  shared/
    state/        SSOT slices: profile · xp · missions · achievements · exploration · hydration
    services/     api_service · territory_realtime_service · step_claim_queue · batch_drain_service
    models/       territory_cell · daily_mission · achievement · user
api/MyLoop.Api/
  Controllers/    Claims · Territory · Missions · Achievements · Leaderboard · Users
  Services/       TerritoryService · MissionService · HexGridService · AchievementService · …
  Hubs/           TerritoryHub (region + per-user groups)
  Entities/ Data/ EF model (AppDbContext) · Program.cs (DI, auth, schema bootstrap)

## Data Lifecycle (8 thresholds)
A UI gesture → B Riverpod slice → C Dio/serialize → D REST or SignalR boundary →
E .NET controller (JWT-derived caller, DTO bind) → F service + H3 spatial calc →
G EF Core txn (Serializable + advisory lock) → H SignalR/FCM broadcast → back to A/B.

## Local Development
### API
cd api/MyLoop.Api
cp appsettings.Development.example.json appsettings.Development.json   # set DefaultConnection
dotnet run                                  # schema auto-bootstraps (EnsureCreated + idempotent DDL)
# Health: GET http://localhost:5000/

### Mobile
cd mobile && flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:5000

### Device → local API over ngrok (real GPS testing)
ngrok http 5000
flutter run --dart-define=API_BASE_URL=https://<id>.ngrok.app
# CORS: add the ngrok origin to Cors:AllowedOrigins (browser builds only; native ignores CORS).

## Spatial Index Optimization (run once per environment)
CREATE INDEX IF NOT EXISTS "IX_TerritoryCells_Geo_Brin"
  ON "TerritoryCells" USING BRIN ("CenterLat","CenterLng") WITH (pages_per_range=128);
CREATE INDEX IF NOT EXISTS "IX_TerritoryCells_Decay"
  ON "TerritoryCells" ("LastRefreshedAt","DecayDays");
-- Keystone idempotency constraint (see CONTRIBUTING):
CREATE UNIQUE INDEX IF NOT EXISTS "UX_DailyMissions_User_Date_Type"
  ON "DailyMissions" ("UserId","Date","Type");

## Brand
Primary #00D4AA · Primary-dark #00B894 · Accent (violet) #6C5CE7
Spatial: H3 res-11 (~4,234 m²/hex) · cooldown CellCooldownHours · decay default 7 days.

## Architectural Rules (non-negotiable) — see CONTRIBUTING.md
1. ONE store per domain. Stats live in profileSlice ONLY; widgets read derived providers.
   Never add a second hexCount/streak field to another Notifier.
2. Every channel (HTTP, SignalR, FCM) funnels into the same slice reducer. Server deltas
   carry ABSOLUTE totals and are authoritative; client math is optimistic-only.
3. SignalR connection is owned by auth state (connect on login / dispose on logout),
   never by a screen's lifecycle.
4. Always dispose StreamSubscriptions, Timers, and PageControllers in dispose().
5. H3 cell IDs cross the wire as STRINGS on every channel. Parse string|num on the client.
6. Mutations are idempotent: every create-or-progress endpoint is backed by a UNIQUE
   constraint, never by check-then-act. Read-modify-write on User happens INSIDE the
   per-user advisory-lock transaction.
7. The acting user is ALWAYS resolved from the Firebase JWT (ICurrentUser); request-body
   user IDs are ignored. SignalR group joins must verify caller == requested userId.
----------

## License

Private repository. All rights reserved.
