# 🔍 MyLoop — Comprehensive Architectural Review

> **Review Date**: June 9, 2026
> **Branch**: `develop`
> **Methodology**: 3 parallel deep-dive agents (Backend API, Flutter Frontend, Cross-Stack Contract) each read every file, cross-referenced findings, and verified issues across the full stack.

---

## Executive Summary

This review uncovered **35+ architectural issues**, of which **7 are CRITICAL** — meaning they cause data corruption, data loss, or application crashes in production. The issues are NOT nitpicks; they represent fundamental architectural problems that will compound over time and make the application increasingly unreliable.

The three most dangerous systemic problems are:

1. **The hex count — the game's PRIMARY metric — is a denormalized counter that drifts permanently** due to race conditions, decay cleanup conflicts, and lack of reconciliation.
2. **GPS data is permanently lost** when network requests fail during batch drain, because points are removed from the queue BEFORE the API call succeeds.
3. **The batch-step endpoint (the main gameplay endpoint) has NO anti-cheat validation**, allowing GPS spoofers to claim hexes anywhere in the world.

```
Severity Distribution:
  ■■■■■■■ CRITICAL (7)   — Data corruption, crashes, security bypass
  ■■■■■■■■■■■■ HIGH (12) — Broken features, stale data, silent failures
  ■■■■■■■■ MEDIUM (8)    — UX issues, tech debt, missing validation
```

---

## 🚨 Section 1: Data Integrity & Race Conditions

These issues cause the game's core metrics to become permanently wrong.

---

### CRITICAL-1: Non-Atomic HexCount Updates — Race Condition on Concurrent Claims

> **Severity**: 🔴 CRITICAL
> **Backend**: [TerritoryService.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Services/TerritoryService.cs)
> **Entity**: [User.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Entities/User.cs)

`User.HexCount` is modified with in-memory `+=` and then written via EF Core's `SaveChangesAsync()`. This generates a SQL `SET HexCount = @value` (not `SET HexCount = HexCount + @delta`).

```csharp
// TerritoryService.cs — inside ProcessBatchStepClaim
user.HexCount += newCellCount - stolenBackCount;
user.TotalHexesCaptured += newCellCount;
user.TotalHexesStolen += stolenCount;
user.DistanceKm += distanceKm;
// ...
await _db.SaveChangesAsync();
```

**What goes wrong**: If two batch-step requests from the same user arrive concurrently (network retry, or timer fires while previous request is in-flight):

```
Request A: loads HexCount=100, adds 5 → writes HexCount=105
Request B: loads HexCount=100, adds 3 → writes HexCount=103 (OVERWRITES A's result)
Actual: 103 (should be 108)
```

The same race exists for the **victim's HexCount** when cells are stolen:

```csharp
victim.HexCount = Math.Max(0, victim.HexCount - 1);
```

Two attackers stealing from the same victim simultaneously will both load the same HexCount and one decrement will be silently lost.

> [!CAUTION]
> This is a **permanent, compounding drift**. Every race condition occurrence permanently shifts the hex count by the number of lost increments/decrements. There is no self-healing mechanism.

**Fix needed**: Use raw SQL `UPDATE Users SET HexCount = HexCount + @delta WHERE Id = @id` or use EF Core's `ExecuteUpdateAsync` with relative increments, or wrap in `SERIALIZABLE` transactions with retry logic.

---

### CRITICAL-2: Denormalized HexCount Never Reconciled With Actual Ownership

> **Severity**: 🔴 CRITICAL
> **Backend**: [TerritoryService.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Services/TerritoryService.cs), [DecayCleanupService.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Services/DecayCleanupService.cs)

`User.HexCount` should always equal `COUNT(*) FROM TerritoryCells WHERE OwnerId = userId`. But it's maintained manually across multiple code paths:

| Code Path | Operation | Can Drift? |
|-----------|-----------|------------|
| `ProcessBatchStepClaim` | `user.HexCount += newCells - stolenBack` | ✅ Race condition (CRITICAL-1) |
| `DecayCleanupService` | `user.HexCount -= expiredCount` | ✅ Races with concurrent claims |
| Account deletion | Cascade delete | N/A (user gone) |

There is **no periodic reconciliation job** that recalculates `HexCount = SELECT COUNT(*) FROM TerritoryCells WHERE OwnerId = @id`.

**Impact**: The hex count — displayed on the home tab, profile, leaderboard, and used for achievement thresholds — becomes permanently wrong. The leaderboard ranks players by a number that doesn't reflect reality.

**Fix needed**: 
1. Add a reconciliation background job: `UPDATE Users u SET HexCount = (SELECT COUNT(*) FROM TerritoryCells t WHERE t.OwnerId = u.Id)`
2. Or eliminate the denormalized counter and always compute from TerritoryCells (with a covering index for performance)

---

### CRITICAL-3: GPS Points Permanently Lost on Network Failure

> **Severity**: 🔴 CRITICAL
> **Frontend**: [batch_drain_service.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/services/batch_drain_service.dart), [step_claim_queue.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/services/step_claim_queue.dart)

The batch drain service removes points from the queue **before** the API call succeeds:

```dart
// batch_drain_service.dart — _drain()
final points = await _queue.drainAll(); // ← Points removed from queue HERE
if (points.isEmpty) return;

final request = BatchStepRequest(
  userId: _userId!,
  localDate: _localDate(),
  points: points,
);

await _api.claimBatchStep(request); // ← If this FAILS, points are GONE
```

If the API call throws (network error, server error, timeout), the GPS points are permanently lost. The user walked those steps but they will never be claimed.

Additionally, the `_retryCount` is never reset to 0 after a successful drain, so backoff durations accumulate permanently:

```dart
} catch (e) {
  _retryCount++;  // Never reset on success
  final delay = Duration(seconds: math.min(30, math.pow(2, _retryCount).toInt()));
```

> [!WARNING]
> A user walking for 30 minutes in an area with spotty cell coverage could lose 100+ GPS points per network failure, meaning entire sections of their walk produce zero hex captures.

**Fix needed**: 
1. Use a "peek-then-acknowledge" pattern: peek points, send to API, only remove after success
2. Reset `_retryCount = 0` after successful drain
3. On failure, return points to the queue

---

## 🔗 Section 2: Cross-Stack Contract Mismatches

These issues cause runtime crashes due to type mismatches between frontend and backend.

---

### CRITICAL-4: H3 CellId Type Chaos — `long` vs `int` vs `String` Across Stack

> **Severity**: 🔴 CRITICAL
> **Backend**: [TerritoryCell.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Entities/TerritoryCell.cs) — `CellId: long`
> **Frontend**: [territory_cell.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/models/territory_cell.dart) — `cellId: int`, [trail_claim_response.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/models/trail_claim_response.dart) — `cellId: String?`

H3 indices are 64-bit integers (e.g., `631243847852867583`). The types are inconsistent:

| Location | Type | Risk |
|----------|------|------|
| Backend Entity | `long` (C#) | N/A — correct |
| Backend JSON | `number` (64-bit) | N/A — correct |
| Frontend `TerritoryCell` | `int` (Dart) | ✅ Works on native (64-bit), ❌ **BREAKS on Flutter Web** (53-bit JS) |
| Frontend `StepClaimResult` | `String?` | ❌ Type mismatch — backend sends `number`, Dart expects `String` |
| Frontend `HexOverlay` | ? | Need to verify consistency |

**Within the same Flutter app**, `cellId` is sometimes parsed as `int` and sometimes as `String`, depending on which model you're looking at. This means:
- `StepClaimResult.fromJson` will crash if `cellId` is a JSON number (not a string)
- `TerritoryCell.fromJson` will crash if `cellId` overflows 53-bit on web
- Comparing cell IDs across models will fail (`int == String` → always false)

**Fix needed**: Standardize on `String` everywhere (serialize H3 indices as strings from the backend using a custom JsonConverter), or standardize on `int` everywhere with explicit `(json['cellId'] as num).toInt()` parsing.

---

### CRITICAL-5: SignalR UserStatsDelta Field Names Don't Match Frontend

> **Severity**: 🔴 CRITICAL
> **Backend**: [TerritoryNotifier.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Services/TerritoryNotifier.cs) — sends `BatchStats` or `UserStatsPayload`
> **Frontend**: [territory_realtime_service.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/services/territory_realtime_service.dart) — parses `UserStatsDelta`

The backend sends a stats payload with property names:
```csharp
// BatchStats.cs (or UserStatsPayload)
TotalCaptured   → JSON: "totalCaptured"
TotalStolen     → JSON: "totalStolen"
```

The frontend expects:
```dart
totalCaptured: data['totalHexesCaptured'] as int,  // ← WRONG KEY
totalStolen: data['totalHexesStolen'] as int,       // ← WRONG KEY
```

The frontend accesses `totalHexesCaptured` but the backend sends `totalCaptured`. This null-casts to `int` and **crashes the app** every time a SignalR stats delta is received.

**Fix needed**: Align field names — either rename the backend properties to `TotalHexesCaptured`/`TotalHexesStolen`, or fix the frontend to use `totalCaptured`/`totalStolen`.

---

### CRITICAL-6: User ID Type Mismatch — Frontend Uses `int`, Backend Uses `Guid`

> **Severity**: 🔴 CRITICAL
> **Backend**: [User.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Entities/User.cs) — `Id: Guid`
> **Frontend**: [api_service.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/services/api_service.dart) — `userId: int`

```dart
// api_service.dart
Future<Map<String, dynamic>> getUser(int userId) async {
  final response = await _dio.get('/api/users/$userId');
```

```csharp
// UsersController.cs
[HttpGet("{id}")]
public async Task<IActionResult> GetUser(Guid id) => ...
```

Sending `/api/users/123` when the route expects a GUID will fail. Either:
1. The app has a separate numeric ID system not visible in the entity (unlikely)
2. The app stores the Guid as a string in Flutter and `.toString()` is called (need to verify)
3. All authenticated API calls are fundamentally broken

**This needs immediate verification** by checking what `userId` value the Flutter app actually passes in API calls.

---

## 🛡️ Section 3: Anti-Cheat & Security

---

### CRITICAL-7: Batch-Step Endpoint Has ZERO Anti-Cheat Validation

> **Severity**: 🔴 CRITICAL
> **Backend**: [TerritoryService.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Services/TerritoryService.cs), [PathValidationService.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Services/PathValidationService.cs)

The `PathValidationService` implements 3-layer anti-cheat (speed, duration, smoothness). But it is **only called for the full `POST /api/claims` endpoint** (loop claims). The `POST /api/claims/batch-step` endpoint — which is the **primary gameplay endpoint** used during walks — processes GPS points WITHOUT any anti-cheat:

```csharp
// ProcessBatchStepClaim — NO call to PathValidationService
public async Task<BatchStepClaimResponse> ProcessBatchStepClaim(
    Guid userId, string localDate, List<GeoCoordinate> points)
{
    // Directly processes points — no speed check, no duration check, no smoothness check
    for (int i = 0; i < points.Count; i++)
    {
        var pt = points[i];
        var cellId = _hexGrid.PointToCell(pt.Lat, pt.Lng);
        // ... claim cell
    }
}
```

A GPS spoofer can:
1. Send fake coordinates to batch-step: `{points: [{lat: 48.8566, lng: 2.3522}, {lat: 40.7128, lng: -74.0060}]}` (Paris to New York)
2. Claim hexes anywhere in the world
3. No speed check will reject this because there IS no speed check

> [!CAUTION]
> This completely undermines the anti-cheat system described in the spec. The 3-layer validation is useless because the main claim path doesn't use it.

**Fix needed**: Add speed validation between consecutive batch points (distance / time-since-last-point ≤ max speed). Add coordinate bounds checking. Add rate limiting per user.

---

### HIGH-1: SetHome Trusts Client Coordinates — Leaderboard Manipulation

> **Severity**: 🟠 HIGH
> **Backend**: [UsersController.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Controllers/UsersController.cs)

```csharp
[HttpPost("{id}/home")]
public async Task<IActionResult> SetHome(Guid id, [FromBody] SetHomeRequest request)
{
    // No validation that coordinates are near user's actual GPS
    user.HomeLat = request.Lat;
    user.HomeLng = request.Lng;
```

A user can set their home to any city where they want to dominate the leaderboard, without ever physically being there.

---

### HIGH-2: No Rate Limiting on Claim Endpoints

> **Severity**: 🟠 HIGH
> **Backend**: [ClaimsController.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Controllers/ClaimsController.cs), [Program.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Program.cs)

The spec mentions `MaxClaimsPerDay = 20` in `GameConstants`, but there's no evidence this is checked in `ProcessBatchStepClaim`. The batch-step endpoint doesn't count how many batches have been submitted today.

---

## ⚡ Section 4: State Management & Real-Time

---

### HIGH-3: Dual-Write Race — HTTP Response AND SignalR Both Update Same Providers

> **Severity**: 🟠 HIGH
> **Frontend**: [journey_controller.dart](file:///c:/Workspace/MyLoop/mobile/lib/features/journey/journey_controller.dart), [user_realtime_listener.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/services/user_realtime_listener.dart)

When a batch-step HTTP response arrives, `_applyBatchResult()` updates:
- `userProfileProvider` (hex count, streak, distance)
- `xpSliceProvider` (XP, level)
- `missionsSliceProvider` (mission progress)
- `achievementsSliceProvider` (unlocks)

**Simultaneously**, the backend fires SignalR events that `user_realtime_listener.dart` uses to update **the exact same providers**.

```
Timeline:
  T1: HTTP response arrives → updates hexCount to 105
  T2: SignalR UserStatsDelta arrives (same data) → updates hexCount to 105 again
  
  OR WORSE:
  T1: HTTP response from batch A → updates hexCount to 105
  T2: HTTP response from batch B → updates hexCount to 108
  T3: SignalR delta from batch A arrives (stale) → OVERWRITES hexCount back to 105
```

**Impact**: UI flickers, stale SignalR data can overwrite newer HTTP data.

**Fix needed**: Either:
1. Don't process SignalR deltas while a batch drain is in-flight (debounce)
2. Add a monotonic version/sequence number and ignore older updates
3. Only use one update path (e.g., always use HTTP response for self-actions, SignalR only for other-player updates)

---

### HIGH-4: Real-Time Hex Ownership Changes NOT Rendered on Journey Map

> **Severity**: 🟠 HIGH
> **Frontend**: [territory_realtime_service.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/services/territory_realtime_service.dart), [journey_controller.dart](file:///c:/Workspace/MyLoop/mobile/lib/features/journey/journey_controller.dart)

The architecture doc states: *"UI instantly shows friend's steal on YOUR map"*. But `journey_controller.dart` does NOT subscribe to `territoryRealtimeService.onHexChanges`. The `HexOwnershipChanged` events are emitted to a stream that nobody in the journey flow listens to.

**Impact**: If another player steals your hex while you're on a walk, your map doesn't update until you pan/zoom to trigger a new `getTerritories()` viewport query.

---

### HIGH-5: Two Sources of Truth for User Profile Data

> **Severity**: 🟠 HIGH
> **Frontend**: [user_state.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/services/user_state.dart), [profile_slice.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/state/profile_slice.dart)

Both `userProfileProvider` and `profileSliceProvider` hold user profile data:
- `userProfileProvider` (in `user_state.dart`) — updated by SignalR deltas and batch-step responses
- `profileSliceProvider` (in `profile_slice.dart`) — loads from `GET /api/users/{id}`

These can contain different values for the same fields (hex count, streak, level) because they're updated from different sources at different times.

---

### HIGH-6: SignalR Stream Subscriptions Leak on Auth State Change

> **Severity**: 🟠 HIGH
> **Frontend**: [user_realtime_listener.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/services/user_realtime_listener.dart)

When `build()` is re-invoked (auth state change), old stream subscriptions are not cancelled before creating new ones:

```dart
void _subscribe() {
  // OLD subscriptions from previous build() call are still active!
  _statsSub = realtime.onUserStats.listen((delta) { ... }); // Creates NEW subscription
  _xpSub = realtime.onXp.listen((delta) { ... });
```

Each auth state change doubles the number of active listeners. State updates fire 2x, 3x, 4x...

**Fix needed**: Cancel existing subscriptions in `build()` before calling `_subscribe()`:
```dart
_statsSub?.cancel();
_xpSub?.cancel();
_missionsSub?.cancel();
_achievementsSub?.cancel();
_subscribe();
```

---

### HIGH-7: Exploration Stats Cache Never Invalidates

> **Severity**: 🟠 HIGH
> **Frontend**: [exploration_slice.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/state/exploration_slice.dart)

```dart
Future<void> fetch(int userId, double lat, double lng) async {
  if (state.isLoaded) return; // ← NEVER re-fetches once loaded
```

Once exploration data is fetched, it's cached forever. If the user walks to a different neighborhood, city, or country, they still see the original exploration stats.

---

## 💾 Section 5: Data Loss & Reliability

---

### HIGH-8: StepClaimQueue Not Crash-Safe

> **Severity**: 🟠 HIGH
> **Frontend**: [step_claim_queue.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/services/step_claim_queue.dart)

```dart
Future<void> _persist() async {
  final file = await _getFile();
  final lines = _queue.map((p) => jsonEncode(p)).join('\n');
  await file.writeAsString(lines); // ← Full file rewrite each time
}
```

If the app is force-killed during `writeAsString()`, the file can be partially written. On next launch, parsing the truncated file will fail, potentially losing all queued GPS points.

**Fix needed**: Write to a temporary file first, then atomically rename it over the original.

---

### HIGH-9: Leaderboard Refresh is Non-Transactional Delete-Then-Insert

> **Severity**: 🟠 HIGH
> **Backend**: [LeaderboardService.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Services/LeaderboardService.cs)

```csharp
// Delete old entries
_db.LeaderboardEntries.RemoveRange(oldEntries);
// Re-create entries
foreach (var user in users) { _db.LeaderboardEntries.Add(...); }
await _db.SaveChangesAsync();
```

No explicit transaction. If the server crashes between delete and insert, all leaderboard data for the day is lost. Also loads ALL users into memory — OOM risk at scale.

---

### HIGH-10: SignalR Broadcast Failures Are Silent and Unrecoverable

> **Severity**: 🟠 HIGH
> **Backend**: [TerritoryNotifier.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Services/TerritoryNotifier.cs)

```csharp
await _hubContext.Clients.Group(group.Key)
    .SendAsync("HexOwnershipChanged", group.ToList());
// No try/catch — if one region fails, all subsequent regions are skipped
```

No error handling, no retry, no fallback. If SignalR fails to deliver, the client's map state becomes stale until they manually refresh.

---

### HIGH-11: Daily Mission Timezone Mismatch

> **Severity**: 🟠 HIGH
> **Backend**: [MissionService.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Services/MissionService.cs)

```csharp
var today = DateOnly.FromDateTime(DateTime.UtcNow); // ← UTC, not user's local time
```

The client sends `localDate` in batch-step requests, but `MissionService` uses server UTC to determine "today". Users in UTC+12 will have missions that reset at noon local time.

---

## 🏗️ Section 6: Design & Architecture Debt

---

### MEDIUM-1: No Explicit Database Transactions

> **Backend**: [TerritoryService.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Services/TerritoryService.cs)

The entire claim pipeline relies on EF Core's implicit `SaveChangesAsync()` transaction. No `BeginTransactionAsync()` is used. This means:
- No retry logic for deadlocks
- No explicit isolation level (defaults to READ COMMITTED — allows phantom reads)
- Any unhandled exception in the claim pipeline rolls back ALL changes, including legitimate cell claims

---

### MEDIUM-2: Claims Table Grows Unboundedly

> **Backend**: [TerritoryService.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Services/TerritoryService.cs)

Every batch-step creates a Claim record. A 30-minute walk generates ~180 claims. With 1000 users, that's 180K claims/day, 65M claims/year. No archival, no partitioning, no cleanup.

---

### MEDIUM-3: Frontend Loop Detector vs Backend Loop Extraction Mismatch

> **Frontend**: [loop_detector.dart](file:///c:/Workspace/MyLoop/mobile/lib/features/journey/loop_detector.dart)

Frontend checks only if `first.distanceTo(last) ≤ 50m`. Backend may extract sub-loops from the path. This means the "Loop Detected!" UI message may not match what the server actually captures.

---

### MEDIUM-4: Silent Failure on Location Permission Denial

> **Frontend**: [journey_controller.dart](file:///c:/Workspace/MyLoop/mobile/lib/features/journey/journey_controller.dart)

```dart
if (!hasPermission) {
  state = state.copyWith(status: JourneyStatus.idle);
  return; // ← No error message to user
```

User taps "Start Journey," nothing happens, no explanation.

---

### MEDIUM-5: API Error Responses Not Parsed or Shown to User

> **Frontend**: [api_service.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/services/api_service.dart)

Backend error messages (e.g., "Anti-cheat: speed violation") are never extracted from DioException responses. Generic error handling loses all diagnostic information.

---

### MEDIUM-6: External Geocoding in Critical Path

> **Backend**: [GeocodingService.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Services/GeocodingService.cs)

Nominatim API call during claim processing — no timeout, no caching, no rate limiting. If Nominatim is slow or down, claim processing blocks.

---

### MEDIUM-7: Frontend Missing Key Backend Game Constants

> **Frontend**: [app_constants.dart](file:///c:/Workspace/MyLoop/mobile/lib/shared/constants/app_constants.dart)

| Constant | Backend Value | Frontend |
|----------|--------------|----------|
| `MaxClaimsPerDay` | 20 | ❌ Missing |
| `CellCooldownHours` | 5.0 | ❌ Missing |
| `MaxClaimAreaM2` | 5,000,000 | ❌ Missing |
| `MinGpsPoints` | 10 | ❌ Missing |
| `MaxViewportCells` | 500 | ❌ Missing |

Users get no client-side feedback about these limits until the backend rejects their request.

---

### MEDIUM-8: Duplicate Walk History Endpoints

> **Backend**: [UsersController.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Controllers/UsersController.cs), [TerritoryController.cs](file:///c:/Workspace/MyLoop/api/MyLoop.Api/Controllers/TerritoryController.cs)

Both `GET /api/users/{id}/claims` and `GET /api/territories/claims/{userId}` serve walk history. They may return different formats, causing confusion.

---

## 📋 Prioritized Fix Roadmap

### Phase 1: Stop the Bleeding (Week 1)

| Priority | Fix | Impact |
|----------|-----|--------|
| P0 | Fix batch-drain to not lose GPS points on failure (peek-then-ack pattern) | Prevents data loss |
| P0 | Add anti-cheat validation to batch-step endpoint | Prevents cheating |
| P0 | Fix SignalR field name mismatch (`totalCaptured` vs `totalHexesCaptured`) | Prevents crash |
| P0 | Standardize CellId type to `String` across entire stack | Prevents crash |
| P0 | Verify/fix User ID type (`int` vs `Guid`) across entire stack | Prevents all API failures |

### Phase 2: Data Integrity (Week 2)

| Priority | Fix | Impact |
|----------|-----|--------|
| P1 | Use atomic SQL for hex count updates (`HexCount = HexCount + @delta`) | Prevents counter drift |
| P1 | Add hex count reconciliation background job | Self-healing |
| P1 | Fix SignalR subscription leak in `user_realtime_listener.dart` | Prevents memory leak |
| P1 | Fix dual-write race (add sequence numbers or debounce) | Prevents stale data |
| P1 | Wrap leaderboard refresh in explicit transaction | Prevents data loss |

### Phase 3: Robustness (Week 3)

| Priority | Fix | Impact |
|----------|-----|--------|
| P2 | Use crash-safe file writes for StepClaimQueue | Prevents data loss |
| P2 | Add try/catch + retry to SignalR broadcasts | Improves reliability |
| P2 | Fix mission timezone to use client's local date | Correct UX |
| P2 | Add HexOwnershipChanged listener to journey map | Real-time map updates |
| P2 | Consolidate user profile into single source of truth | Simpler state management |

### Phase 4: Polish (Week 4)

| Priority | Fix | Impact |
|----------|-----|--------|
| P3 | Show user-friendly error messages from API rejections | Better UX |
| P3 | Add client-side validation for game constants | Fewer wasted API calls |
| P3 | Add geocoding cache + timeout | Performance |
| P3 | Add claims table archival/partitioning strategy | Scalability |
| P3 | Remove duplicate walk history endpoint | Code clarity |
| P3 | Invalidate exploration cache on significant location change | Correct data |

---

## Architecture Diagram: Where Issues Live

```
┌─ FLUTTER APP ─────────────────────────────────────────────────────────┐
│                                                                        │
│  GPS → StepClaimQueue ──→ BatchDrainService ──→ ApiService             │
│         ❌ CRITICAL-3        ❌ CRITICAL-3       ❌ CRITICAL-4,5,6     │
│         (crash-unsafe)       (loses points)      (type mismatches)     │
│                                                                        │
│  Providers: userProfile ← ← ← ← HTTP + SignalR = ❌ HIGH-3 (race)    │
│             xpSlice ← ← ← ← ← ─┘                                    │
│             missionsSlice                                              │
│             profileSlice ← ← ← ← ❌ HIGH-5 (dual source of truth)    │
│                                                                        │
│  user_realtime_listener ← ← ← ← ❌ HIGH-6 (subscription leak)        │
│  explorationSlice ← ← ← ← ← ← ❌ HIGH-7 (never invalidates)         │
│  journey map ← ← ← ← ← ← ← ← ❌ HIGH-4 (no real-time hex updates)  │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼ HTTP + SignalR
┌─ .NET API ────────────────────────────────────────────────────────────┐
│                                                                        │
│  ClaimsController → TerritoryService.ProcessBatchStepClaim()           │
│                     ❌ CRITICAL-1 (race condition on HexCount)         │
│                     ❌ CRITICAL-2 (denormalized, never reconciled)     │
│                     ❌ CRITICAL-7 (NO anti-cheat on batch-step!)       │
│                                                                        │
│  TerritoryNotifier → SignalR broadcasts                                │
│                      ❌ HIGH-10 (silent failures)                      │
│                      ❌ CRITICAL-5 (field name mismatch)               │
│                                                                        │
│  MissionService → ❌ HIGH-11 (timezone mismatch)                       │
│  LeaderboardService → ❌ HIGH-9 (non-transactional refresh)            │
│  DecayCleanupService → ❌ CRITICAL-2 (races with claims)               │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```




Phase 1: Security & Crash Fixes (P0)
 CRITICAL-1: Extract UserId from JWT in all controllers, not request body
 CRITICAL-2: Add [Authorize] to MissionsController
 CRITICAL-3: Fix user deletion — add missing table deletions (ExploredCells, DailyMissions, UserAchievements, DeviceTokens)
 CRITICAL-4: Fix SignalR group name mismatch (Firebase UID vs App GUID)
 CRITICAL-7: Fix batch-drain: peek-then-acknowledge pattern
 CRITICAL-8: Fix StepClaimQueue: atomic file writes (temp + rename)
 CRITICAL-9: Standardize CellId type to String across Flutter models
Phase 2: Data Integrity (P1)
 CRITICAL-5: Use atomic SQL for HexCount updates
 CRITICAL-6: Add HexCount reconciliation background job
 HIGH-3: Add transactions to ProcessTrailClaim and ProcessStepClaim
 HIGH-8: Cancel old SignalR subscriptions before re-subscribing
 HIGH-11: Update DistanceKm in Trail/Step/Batch claims
 HIGH-12: Fix leaderboard: transaction, scheduled refresh, counter inflation
 HIGH-14: Remove/gate dev test endpoints
Phase 3: Feature Completeness (P2)
 HIGH-5: Add dual-write deduplication (ignore stale SignalR after HTTP response)
 HIGH-6: Subscribe journey map to HexOwnershipChanged
 HIGH-7: Consolidate user profile into single source of truth
 HIGH-9: Add exploration stats cache invalidation
 CRITICAL-10: Reconcile achievement definitions (remove dead 100-item list)
 HIGH-13: Add inter-point speed validation to batch-step
 HIGH-4: Add concurrency retry logic to hex claims
Phase 4: Polish (P3)
 M1: Lock down CORS for production
 M2: Add claims table archival strategy
 M4: Show error on location permission denial
 M5: Parse and show API error responses
 M6: Add geocoding cache + timeout
 M7: Add client-side game constant validation
 M8: Fix mission timezone to use client localDate
 M9: Gate GetByFirebaseUid behind auth
 M11: Fix CaptureInOneWalk mission semantics
 M12: Fix leaderboard to not load all users into memory



 





 ------ All issues before this are fixed(New Issues as of 11thJune 2026 10 pm)---


PART 2: COMPREHENSIVE REPOSITORY ISSUES LOG & TAXONOMY

Issue ID: CRIT-1
Subsystem Component: Riverpod SSOT (B↔H)
File & Line Trace Context: profile_slice.dart:58, hydration.dart:28,46, home_tab.dart:140,833, journey_screen.dart:118,130
Root Cause Analysis (End-to-End Mechanics): Stats duplicated across userProfileProvider + profileSliceProvider. SignalR UserStatsDelta & hydration write the
  slice; Home/profile/leaderboard/history read the profile. Only a post-loop-claim manual copy reconciles them → passive/victim/cross-device pushes never reach
  Home. This is the Hex discrepancy bug.
Structural Impact: Stats divergence across tabs; victim hex losses invisible until manual refresh
Verified Cross-Stack Resolution Plan (Production Fix): Strip nummake profileSlice the sole store fed by all channels; Home reads
  hexCountProvider derived view (Part 1 §1)
────────────────────────────────────────
Issue ID: CRIT-2
Subsystem Component: SignalR auth / IDOR (D↔H)
File & Line Trace Context: TerritoryHub.cs:36-44 (JoinUserGroup)
Root Cause Analysis (End-to-End Mechanics): Checks IsAuthenticatr maps to the requested userId. App-Guid OwnerId leaks via
  TerritoryCellResponse/leaderboard, so an attacker can subscribe to any victim's user_{guid} group and receive their stats/XP/mission/achievement deltas.
Structural Impact: Cross-account personal-data leak (authz/IDOR)
Verified Cross-Stack Resolution Plan (Production Fix): Resolve caller via ICurrentUser from Context.User; reject if caller != userId; ignore the
client-supplied
  id entirely
────────────────────────────────────────
Issue ID: CRIT-3
Subsystem Component: EF model / Missions (G)
File & Line Trace Context: AppDbContext.cs:94, Program.cs:284-286, MissionService.cs:57-74
Root Cause Analysis (End-to-End Mechanics): DailyMission has onlindex → the catch(DbUpdateException) recovery is dead code.
  GetMissions runs outside the advisory lock; two first-of-day requests both insert 3 rows.
Structural Impact: Duplicate daily missions (6+/day), double all
Verified Cross-Stack Resolution Plan (Production Fix): Add UNIQUE(UserId,Date,Type); idempotent generate-or-reload (Part 1 §2b)
────────────────────────────────────────
Issue ID: HIGH-1
Subsystem Component: Serialization / 64-bit keys (C↔E)
File & Line Trace Context: territory_cell.dart:52,62; REST TerritoryCellResponse; vs SignalR TerritoryService.cs:1376
Root Cause Analysis (End-to-End Mechanics): REST emits cellId/paDart as int; SignalR emits h3Index as string. Res-11 ids > 2⁵³ →
  silent truncation on Flutter web (mobile/web/ present) during JSON decode; brittle number/string split across channels.
Structural Impact: Wrong-cell ownership / map corruption on web;
Verified Cross-Stack Resolution Plan (Production Fix): Emit H3 ids as strings on REST via JsonConverter; Dart parse string|num (Part 1 §3a)
────────────────────────────────────────
Issue ID: HIGH-2
Subsystem Component: Realtime lifecycle (A)
File & Line Trace Context: journey_screen.dart _connectRealtime/dispose; doc territory_realtime_service.dart:7
Root Cause Analysis (End-to-End Mechanics): SignalR connect/disccreen, not auth. Leaving the screen tears down the connection → no
  personal deltas anywhere else, amplifying CRIT-1.
Structural Impact: No live updates on Home/leaderboard; stale UI
Verified Cross-Stack Resolution Plan (Production Fix): Own the ctimeConnectionProvider); remove per-screen disconnect (Part 1 §1)
────────────────────────────────────────
Issue ID: HIGH-3
Subsystem Component: Map state apply (B↔H)
File & Line Trace Context: hex_territory_manager.dart:168-175
Root Cause Analysis (End-to-End Mechanics): On another player's capture, the hex is removed from the previous owner's color group but never added to the new
  owner's group; relies on a future viewport reload.
Structural Impact: Contested hexes blank out on the map until reload
Verified Cross-Stack Resolution Plan (Production Fix): Render imColor+center; id-based match (Part 1 §3b)
────────────────────────────────────────
Issue ID: HIGH-4
Subsystem Component: Mission progress drift (F)
File & Line Trace Context: TerritoryService.cs:110-118 (loop) vsrail)
Root Cause Analysis (End-to-End Mechanics): MaintainStreak recorded on step/batch but not on loop ProcessClaim; trail path omits
  WalkDistance/CaptureInOneWalk/MaintainStreak and never increme
Structural Impact: Mission completion & leaderboard distance depend on which claim path the player used
Verified Cross-Stack Resolution Plan (Production Fix): Extract os(...) helper called by all four paths
────────────────────────────────────────
Issue ID: MED-1
Subsystem Component: Resource teardown (A)
File & Line Trace Context: home_tab.dart:447-458 _MissionCountdo
Root Cause Analysis (End-to-End Mechanics): Stream.periodic subscription created in initState, never cancelled.
Structural Impact: Leaked timer per Home-tab mount
Verified Cross-Stack Resolution Plan (Production Fix): Store subscription; cancel in dispose()
────────────────────────────────────────
Issue ID: MED-2
Subsystem Component: Claim idempotency (C↔G)
File & Line Trace Context: step_claim_queue.dart, batch_drain_service.dart, TerritoryService.ProcessBatchStepClaim
Root Cause Analysis (End-to-End Mechanics): WAL re-drain after re; idempotency is only accidental (already-owned skip) and breaks
  on steal→re-steal interleave.
Structural Impact: Possible duplicate transfers/XP on retry
Verified Cross-Stack Resolution Plan (Production Fix): Client Idempotency-Key/clientId; UNIQUE(UserId,IdempotencyKey) on Claims, replay stored response (Part 1

  §2c)
────────────────────────────────────────
Issue ID: MED-3
Subsystem Component: Secret in logs (D)
File & Line Trace Context: territory_realtime_service.dart:211
Root Cause Analysis (End-to-End Mechanics): debugPrint('Connectess_token=<JWT>.
Structural Impact: Firebase JWT in device logs
Verified Cross-Stack Resolution Plan (Production Fix): Redact qu
────────────────────────────────────────
Issue ID: MED-4
Subsystem Component: Schema management (G)
File & Line Trace Context: Program.cs:190-323
Root Cause Analysis (End-to-End Mechanics): Schema bootstrapped via EnsureCreated() + idempotent raw ALTER/CREATE; EF migration files exist but are never
  applied. catch {} swallows all DDL errors.
Structural Impact: Snapshot vs live-DB drift; silent migration failures
Verified Cross-Stack Resolution Plan (Production Fix): Adopt db. on DDL errors; keep migrations authoritative
────────────────────────────────────────
Issue ID: MED-5
Subsystem Component: Streak date trust (E↔F)
File & Line Trace Context: TerritoryService.cs:1311-1323 Resolve
Root Cause Analysis (End-to-End Mechanics): Client LocalDate clamped to UTC ±1 day — reasonable, but a client toggling between +1/-1 across requests can nudge
  streak windows.
Structural Impact: Minor streak manipulation surface
Verified Cross-Stack Resolution Plan (Production Fix): Derive frtimezone offset rather than per-request client date
────────────────────────────────────────
Issue ID: LOW-1
Subsystem Component: Advisory-lock key (G)
File & Line Trace Context: TerritoryService.cs:77 etc.
Root Cause Analysis (End-to-End Mechanics): Lock key = BitConverter.ToInt64(userId.ToByteArray(),0) (first 8 GUID bytes); two distinct users could collide
  (~2⁻⁶⁴).
Structural Impact: Negligible false serialization between unrelated users
Verified Cross-Stack Resolution Plan (Production Fix): Hash fulle.g. Xor both halves)
────────────────────────────────────────
Issue ID: LOW-2
Subsystem Component: XP rounding (F)
File & Line Trace Context: TerritoryService.cs:107
Root Cause Analysis (End-to-End Mechanics): (int)(distanceKm * XpPerKmWalked) truncates fractional-km XP each claim.
Structural Impact: Slow XP under-award for short walks
Verified Cross-Stack Resolution Plan (Production Fix): Accumulate fractional XP remainder on User, or round
────────────────────────────────────────
Issue ID: LOW-3
Subsystem Component: Geocoding fan-out (F)
File & Line Trace Context: TerritoryService.cs:1008-1025
Root Cause Analysis (End-to-End Mechanics): GetExplorationStats  a 5 s wall-clock cap; read path, no txn, but unbounded N per
  request.
Structural Impact: Latency spikes on large explorers
Verified Cross-Stack Resolution Plan (Production Fix): Cap neighborhoods per request; precompute area names on write    
