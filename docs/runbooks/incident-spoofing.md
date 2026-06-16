# Runbook: Responding to a GPS-Spoofing / Cheat Wave

Anti-cheat (`PathValidationService`) rejects most spoofed paths at claim time (speed,
duration, smoothness). This runbook covers what to do when cheating gets past it at scale.

## Detect

Signals that a cheat wave is underway:
- A single user's `HexCount` / `TotalHexesCaptured` climbing implausibly fast.
- Claims with suspiciously uniform timing or perfectly smooth-but-fast paths.
- Leaderboard anomalies (a new account topping a city overnight).

## Investigate

- Pull the user's `Claim` rows; inspect `PolygonJson` for unnatural geometry (perfectly
  straight segments, teleport jumps between consecutive claims).
- Cross-check `CellTransfer` history for the affected region.

## Contain

1. **Suspend the account** (Terms of Service §1 permits permanent suspension for spoofing).
2. **Roll back stolen territory** using the `CellTransfer` log — reassign cells to the prior
   owner. (This is *why* every steal must write a transfer row — see
   [../architecture/claim-pipeline.md](../architecture/claim-pipeline.md).)
3. Notify affected players via FCM if material.

## Harden (follow-up)

- Tighten the relevant `AntiCheatConstants` threshold if a systematic bypass is found.
- Record the bypass and fix as a dated entry in [../learnings/phase-1.md](../learnings/phase-1.md).
- Consider server-side cross-claim checks (e.g., impossible travel between consecutive claims).
