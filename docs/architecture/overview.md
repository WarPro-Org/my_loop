# Architecture Overview

MyLoop is a real-world territory-capture game. Players walk closed loops outdoors; the
server validates the path, claims every H3 hexagon inside the loop for the player, and
broadcasts the change to nearby players in real time.

## System diagram

```
┌─────────────────────────────────────────────────────────┐
│  MOBILE (Flutter / Riverpod)                            │
│  ┌──────────┐  ┌───────────┐  ┌──────────────────────┐ │
│  │ GPS      │  │ Map       │  │ SignalR Client        │ │
│  │ Tracking │  │ Rendering │  │ (region subscription) │ │
│  └────┬─────┘  └─────┬─────┘  └──────────┬───────────┘ │
│       └──────────────┼───────────────────┘             │
│                      ▼                                  │
│         API Service (Dio + JWT interceptor)             │
└──────────────────────┼──────────────────────────────────┘
                       │ HTTPS + WebSocket (wss)
┌──────────────────────┼──────────────────────────────────┐
│  BACKEND (.NET 10)   │                                  │
│   Controllers (thin) → Services (9) → EF Core → Postgres │
│   SignalR Hub (region groups)   FCM Push Service         │
└─────────────────────────────────────────────────────────┘
```

## Components

| Layer | Technology | Role |
|-------|-----------|------|
| Mobile | Flutter 3.44 / Dart 3.12 | Single codebase iOS + Android. Renders the map; records GPS; **renders server-authoritative state** (never the source of truth for ownership). |
| State | Riverpod 3.x | Reactive feature slices (`xp`, `missions`, `profile`, `exploration`, `achievements`). |
| Backend | .NET 10 / ASP.NET Core | Thin controllers → 9 interfaced services → EF Core. |
| Database | PostgreSQL 18 | Ownership, claims, transfers, users. |
| Spatial grid | Uber H3 (res-10) | Global uniform hexagons (~65 m wide). See [spatial-model.md](spatial-model.md). |
| Real-time | SignalR (WebSocket) | Region-group broadcast of territory changes. See [realtime.md](realtime.md). |
| Auth | Firebase Authentication | Sign in with Apple + Google. JWT validated server-side. |
| Push | Firebase Cloud Messaging | "Your territory was stolen" while app is closed. |

## Source-of-truth principle

The **server is authoritative** for all ownership. The client records a GPS path and submits
it; the server validates (anti-cheat), computes hexes, assigns ownership in a single DB
transaction, and pushes the result. The client renders what the server says — it must never
optimistically claim territory locally, because a claim can be rejected by anti-cheat or lose
a race to another player.

## Key flows

- **Claim:** [claim-pipeline.md](claim-pipeline.md)
- **Spatial queries & indexing:** [spatial-model.md](spatial-model.md)
- **Live map updates & reconnect:** [realtime.md](realtime.md)
