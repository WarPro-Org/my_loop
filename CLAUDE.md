# MyLoop — CLAUDE.md

## Project Overview

MyLoop is a real-world GPS territory-capture game ("Pokémon GO meets Risk meets Strava") with
a Flutter mobile client and a .NET 10 REST API backend. Players walk a closed loop outdoors to
claim the H3 hexagons inside it; other players can steal territory, with real-time map updates
over SignalR and push notifications via FCM. Auth is handled via Firebase JWT (Sign in with
Apple + Google). The project is in closed beta.

---

## Architecture

```
my_loop/
  api/MyLoop.Api/     ← .NET 10 REST API (C#)
  mobile/             ← Flutter app (Dart)
  tests/              ← Shared test suite
  scripts/            ← Dev/utility scripts
```

**Mobile stack:** Flutter, Riverpod (state), go_router (navigation), Dio (HTTP), Firebase Auth
**API stack:** .NET 10, Entity Framework (migrations in api/MyLoop.Api/Migrations/), SignalR (Hubs/)
**Auth:** Firebase JWT — API validates tokens on every request

---

## Branch & PR Workflow

- Branch format: `{username}/{short-description}` (e.g. `ashukla/fix-login-flow`)
- **Never push directly to `master`** — branch protection is enforced
- All changes require a PR with at least 1 approval before merging
- Keep PRs focused — one concern per PR

---

## Pre-PR Skill Gate

Before opening **or** merging a PR, run the skill(s) relevant to what the PR touches.
This is a hard gate. Note in the PR description which skills were run.

Skills live in `.claude/skills/` (vendored from [ECC](https://github.com/affaan-m/ECC),
chosen from MyLoop's documented failure classes in `architecturalIssues_11th_June2026.md`).

| If the PR touches… | Run before opening/merging |
|--------------------|----------------------------|
| .NET API code (Controllers / Services / Data) | `dotnet-patterns`, `csharp-testing` |
| DB schema / EF migrations / hex counts | `database-migrations` (verify atomicity + explicit transactions) |
| API endpoints or request/response shapes | `api-design` |
| **Anything crossing .NET ↔ Flutter** (DTOs, SignalR payloads, IDs, game constants) | `api-design` + **manually confirm field names, types (H3 CellId, UserId), and constants match on both sides** |
| Auth, anti-cheat, client-supplied coordinates, rate limits, secrets | `security-review` |
| SignalR / real-time / caches / offline queues | `latency-critical-systems` |
| Flutter / Dart code or Riverpod state | `dart-flutter-patterns`, `flutter-dart-code-review` |
| Error/exception handling or offline durability | `error-handling` |
| **Always — final gate** | `verification-loop` (tests green) + the PR-review skill |

The cross-stack row is a deliberate manual check — contract drift (.NET ↔ Flutter type/field/ID
mismatches) is MyLoop's #1 bug class and no single skill fully owns it. If a skill surfaces an
issue, fix it before pushing.

---

## Running Locally

### API
```bash
cd api/MyLoop.Api
dotnet restore
dotnet run
# Runs on https://localhost:5001 by default
```

### Mobile
```bash
cd mobile
flutter pub get
flutter run
```

> Make sure you have a valid `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
> in the appropriate directories — these are not committed to the repo.

---

## Key Conventions

### Flutter / Dart
- State management: Riverpod only — no raw setState for business logic
- Routing: go_router — all routes defined centrally in `lib/app/`
- Feature structure: `lib/features/{feature}/` — each feature owns its own screens, providers, and widgets
- HTTP: Dio client via shared service — never call `http` directly
- No hardcoded strings — use constants

### .NET API
- Follow existing Controller → Service → Repository pattern
- New endpoints go in `Controllers/`, business logic in `Services/`, data access in `Data/`
- Add EF migrations for any schema changes: `dotnet ef migrations add <Name>`
- Never commit secrets — use `appsettings.Development.json` (gitignored) for local config

### General
- No commented-out code committed to master
- PR description must explain the "why", not just the "what"
- Run tests before opening a PR

---

## CI

GitHub Actions runs on every PR:
- .NET 10 build + test
- Flutter widget analysis

PRs must pass CI before merging.

---

## Secrets & Config

| File | Purpose | Committed? |
|------|---------|-----------|
| `appsettings.Development.json` | Local API config | No |
| `google-services.json` | Firebase Android config | No |
| `GoogleService-Info.plist` | Firebase iOS config | No |
| `firebase_options.dart` | Firebase Flutter config (auto-generated) | Yes |

Never commit real secrets or API keys.
