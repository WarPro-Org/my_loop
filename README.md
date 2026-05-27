# MyLoop 🌍

A real-time territory capture mobile game — walk around in the real world to claim hexagonal zones on the map. Think Snake.io meets real-world exploration.

## What It Does

- Walk outdoors and your GPS traces a path on a live map
- Complete loops (closed shapes) to capture the territory inside
- Compete on leaderboards — weekly and all-time rankings
- Earn achievements and level up your profile

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile | Flutter 3.x (Dart) — cross-platform iOS/Android/Web |
| State Management | Riverpod (modern Notifier pattern) |
| Navigation | go_router with ShellRoute |
| Maps | flutter_map + OpenStreetMap tiles |
| Backend API | .NET 10 Minimal API (C#) |
| Database | PostgreSQL 18 |
| Auth | Firebase Auth (Google Sign-In, Apple Sign-In) |
| Geo Indexing | H3 hexagonal grid system |

## Project Structure

```
MyLoop/
├── mobile/                     # Flutter app
│   └── lib/
│       ├── app/                # App config, theme, router
│       ├── features/           # Feature-based modules
│       │   ├── auth/           # Login, avatar picker
│       │   ├── home/           # Home tab, shell screen
│       │   ├── journey/        # Active walk recording
│       │   ├── leaderboard/    # Rankings
│       │   └── profile/        # User profile & stats
│       └── shared/             # Cross-feature code
│           ├── models/         # Data classes
│           ├── services/       # API, auth, location
│           └── widgets/        # Reusable UI components
│
├── api/                        # .NET backend
│   └── MyLoop.Api/
│       ├── Endpoints/          # REST endpoint groups
│       ├── Entities/           # Database models
│       ├── Data/               # EF Core DbContext
│       ├── Services/           # Business logic (H3)
│       └── Program.cs          # Bootstrap & DI
```

## Running Locally

### Prerequisites
- Flutter SDK 3.x
- .NET 10 SDK
- PostgreSQL 18
- Firebase project configured

### Backend API
```bash
cd api/MyLoop.Api
dotnet run
# Runs on http://localhost:5048
```

### Mobile App (Web)
```bash
cd mobile
flutter run -d web-server --web-port 9090 --web-hostname 0.0.0.0
# Access at http://<your-ip>:9090
```

### Mobile App (Device)
```bash
cd mobile
flutter run
```

## Color Palette

| Color | Hex | Usage |
|-------|-----|-------|
| Electric Turquoise | `#00D4AA` | Primary brand color |
| Deep Turquoise | `#00B894` | Primary dark variant |
| Mint Frost | `#E0FFF7` | Light backgrounds |
| Royal Purple | `#6C5CE7` | Accent / highlights |

## License

Private repository. All rights reserved.
