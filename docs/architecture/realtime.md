# Real-Time Contract (SignalR)

Live map updates are delivered over a SignalR WebSocket hub (`TerritoryHub`, mapped at
`/hubs/territory`). Push notifications (FCM) are a separate channel for when the app is closed.

## Region groups

Clients subscribe to a **geographic region group** keyed by H3 `ParentCellId` (res-3,
~12 km). When a claim commits, the server broadcasts the territory delta only to the group(s)
covering the affected cells — not to every connected client.

## Auth on the socket

WebSocket upgrade requests cannot set an `Authorization` header, so the Firebase JWT is
passed as the `access_token` query-string parameter and read in `JwtBearerEvents.OnMessageReceived`
(see `Program.cs`). This is only accepted for paths under `/hubs`.

> **Security note:** because the token rides in the query string, **access logs and proxies
> must not log query strings for `/hubs/*`**, or JWTs will leak into logs.

SignalR connections are exempt from the per-user rate limiter (the `/hubs` partition uses
`GetNoLimiter`) so long-lived sockets aren't throttled per message.

## Reconnect & resync — the critical correctness rule

SignalR auto-reconnects, but **deltas sent while a client was disconnected are lost**.
Therefore, on every (re)connect the client **must re-fetch the current viewport** from the
REST API rather than trusting that it has seen every delta.

```
on connected / reconnected:
    1. (re)subscribe to region group(s) for the current viewport
    2. GET /api/territories?<viewport bbox>   # authoritative snapshot
    3. replace local cell state with the snapshot
    4. resume applying live deltas
```

Skipping step 2 produces a silently stale map — the worst failure mode for this game,
because a player thinks they own territory they've actually lost.
