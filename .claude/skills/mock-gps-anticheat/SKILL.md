---
name: mock-gps-anticheat
description: When building or changing a mock/simulated/replayed GPS source, or any client that submits walk paths, ensure the synthetic path satisfies server anti-cheat BY CONSTRUCTION (jitter for bearing std-dev > 2°, real-time pacing for capturedAt speed, retained-point density above minLoopPoints/minGpsPointsPerClaim after the client noise floor, loops close within threshold) and that any mock flag the server honors is environment-gated and branches logging only.
origin: extracted-from-session-2026-06-18
---

# Mock/synthetic GPS must satisfy anti-cheat by construction

## When to Activate
- Building or changing a **mock / simulated / replayed GPS source** (`MockWalkEngine`, GPX replay, a
  test that POSTs a synthetic walk path).
- Any client code that **submits walk paths** the server validates.
- Adding a **test/mock flag the server honors** (header, query param, claim field).

## Why this exists
A synthetic walk that looks obviously fake is **rejected by the same anti-cheat the real app faces**,
so the mock silently captures nothing. The constraints live in the server (`PathValidationService`)
and the client noise filter — not where the mock is written — so they are easy to miss.

## What to verify

| Check | Why | Concretely (MyLoop) |
|-------|-----|---------------------|
| Inject jitter, even on straight routes | `ValidateSmoothness` rejects bearing std-dev < 2° | Gaussian σ≈4 m/fix; straight line FAILS without it |
| Pace in real wall-clock time | `ValidateConsecutivePoints` bounds hops by elapsed `capturedAt`; the client stamps `capturedAt` at retained-point time | ~1 fix/sec; speed under 8.33 m/s cap with margin |
| Keep retained density high enough | client drops fixes closer than `clamp(accuracy, movingMin, movingMax)` (~8 m) | loop perimeter/8 ≥ `minLoopPoints` (20); straight/8 ≥ `minGpsPointsPerClaim` (10) → loop radius ≥ 30 m, straight ≥ 100 m |
| Close loops within tolerance | `LoopDetector.closureThresholdMeters` (50 m) | closed polygon; jitter on start/end ≪ 50 m |
| One plotted route, reused | one-shot fix and live stream must agree | memoize plotted points; don't re-roll RNG per call |
| Environment-gate any honored mock flag | a flag trusted from any client is an evasion vector | honor only outside Production; branch **logging only**, never validation/claim |

## Test it, don't hope
Apply the **same noise-floor dedup the client does** before asserting, then check: bearing std-dev
> 2°, every hop < max-distance cap, loop closes, retained count ≥ minimums — **at config extremes**,
not just defaults. Pin the RNG seed; add a test proving the failure mode (jitter off → std-dev < 2°).
