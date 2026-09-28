# FR1 — Game rules: record

**Status:** done (2026-09-28). Task #201 · spec `requirements.md` → FR1 · design `design/fr1-game-rules.md`
(full matrix, risks and history) · PRs #203 #210 #204 #205 #214 #215 #216 #218 #219, and close-out PR #220
(this record).

This page is the short version: what FR1 put into the app and what a later change must keep true.

## Scope

- **In:** every number today's loop, GPS and anti-cheat code uses moves into one versioned settings section; the
  server and the phone both read it; the phone keeps a copy that works offline.
- **Out (by design):** settings for later features — each later FR adds its own (auto-end FR2, gaps and alarm FR4,
  speed over gaps FR5, guest inactivity FR12). The old claim limits stay in code until FR6.

## What shapes the app

| Area | What exists | Where |
|---|---|---|
| Settings | `GameRules` section in `appsettings.json`: `Version`, `Loop` (4), `Gps` (1), `AntiCheat` (8) | `api/MyLoop.Api/appsettings.json` |
| Server module | Rules module; others use only `IRuleSettings` (`Current`, `GetClientRules()`, `ClientRulesTag`). Internals are internal | `api/MyLoop.Modules.Rules/` |
| Startup check | Server refuses to start if any setting is missing or invalid (presence check + value check) | `GameRulesPresenceValidator`, `GameRulesValidator` |
| Server readers | Loop detection and anti-cheat read every `Loop` and `AntiCheat` number from the rules. The GPS accuracy threshold is phone-only until FR3 | `HexGridService`, `PathValidationService` |
| API | `GET /api/rules` (signed-in): the 5 phone fields only, never anti-cheat numbers (#15); ETag = `{Version}-{hash}`, 304 when unchanged. The phone rejects a reply with a missing or wrongly typed field instead of half-applying it | `RulesController`; contract `tests/contracts/client_rules.json` |
| Phone state | `gameRulesProvider`: built-in copy → saved copy → server copy; refresh on app start, walk start and every hydration (login, onboarding, after a walk, resume, reconnect); one request at a time | `mobile/lib/shared/rules/` |
| Walks | A walk pins its rules as it goes live. Walk start waits for the saved copy to load, then at most 3 s (`walkStartRulesWait`) for the server, else starts on the rules it has | `journey_controller.dart` |
| Saved copy | Written temp-then-rename; a broken or missing file falls back to built-in rules | `rules_store.dart` |

## Decisions that must stay true (or be changed on purpose)

- A running walk never changes rules on the phone; the next walk uses new ones (#20).
- Rules are not tied to a user: sign-out keeps them (the provider is never reset), so the next user never falls back
  to older built-in rules.
- Every phone field is required: a reply missing one, or with a wrong type, is rejected whole and the phone keeps its
  current rules. Old phones ignore fields they don't know (tested). So deploy the server before an app release that adds a
  field; until then new phones keep their current rules.
- The server is the judge: after an app update the phone keeps the last rules the server sent, not newer built-in ones
  (owner decision; newer built-in rules go wrong when the server is behind the app).
- Any refresh failure keeps the current rules; a bug (Dart `Error`) still reaches the crash reporter.
- Values are today's, including the 30 km/h speed limit (FR5 tightens it).
- Tests build the module's internals via `InternalsVisibleTo`, not `AddMyLoopRules`.

## Left to later FRs

- **FR3:** the server drops GPS points below the accuracy threshold (today only the phone does).
- **FR9:** each walk stores its rules version **and a fingerprint of the full rule set** (the version can stay while a
  value changes; FR1's fingerprint covers only the 4 phone settings + version). Until then a redeploy mid-walk
  judges the rest of that walk by the new rules (D2).
- **FR12:** guests can fetch the rules (`GET /api/rules` needs sign-in today).
- **FR5:** the 20–25 km/h speed limit.

## Known limits

- The contract test serializes with ASP.NET's default JSON settings, not the real HTTP pipeline.
- The presence check covers number settings and nested rules classes; a list or text setting needs it extended.
- A walk killed mid-way doesn't resume; its saved points are judged by the server's rules when they arrive (FR9
  makes them be judged by the rules the walk started with).

## How to change a rule

Edit `GameRules` in `appsettings.json` (or a production override), bump `Version`, redeploy. Allowed values: every
number above 0 (`SkipNeighbors` may be 0), `MaxSpeedViolationRate` and `DurationToleranceFactor` above 0 and at
most 1, and the average-speed limit not below the
per-point limit; otherwise the server won't start. The server checks the values at startup; phones pick the change up on their next refresh or walk start. If the built-in phone copy must
change too, update `defaultGameRules` — a test fails when it drifts from `appsettings.json`.

## Tests that guard it

`tests/MyLoop.V01.Tests/FR1/` (server: settings, startup checks, every read setting, contract, module boundary,
endpoint) and `mobile/test/v0_1/fr1/` (phone: saved copy, refresh, every app moment in the design matrix, contract,
ETag). `mobile/test/mock_walk_engine_test.dart` checks dev mock walks against the server's anti-cheat settings.
All run in CI and `scripts/verify.sh`.
