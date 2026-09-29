# Scenario catalogue

This is the one place for every edge case in MyLoop. Look it up whenever you plan, design, code or review.
Every FR design doc answers every ID below, and "PR rules" checks that on every PR.

**Why it exists:** after FR1 was closed with every gate green, a blind audit on 2026-09-29 found 34 gaps
(`docs/versions/1/0.1/audits/2026-09-29-independent-audit.md`). Rules kept only in docs get skipped, so this list is
checked by a machine.

## How to use it

- **Planning (Gate 1):** go through every ID for the requirement. A question that no ID covers means you add a new ID.
- **Design doc (Gate 2):** add a `## Scenarios` table that answers every ID, one row each:
  `| ID | covered / n/a / open / accepted | evidence |`.
  - `covered`: name the test file that proves it, in backticks, e.g. `mobile/test/v0_1/fr1/rules_store_test.dart`.
  - `n/a`: give a reason. The reviewer checks that the reason is true.
  - `open`: name the owner, an FR (e.g. `FR5`) or a task (e.g. `#221`). An `open` may not stay open when its owner
    FR closes.
  - `accepted`: the owner approved leaving it as it is. Say where it was approved (a decision ID, or a task or PR
    number).
- **Each code PR:** the description has a `**Scenarios:**` line listing the IDs this PR covers or changes, or
  `none — <reason>`.
- **Review:** the reviewer checks the PR against the IDs its area touches, not only the diff.
- **New finding** (a review, audit, bug or user report) that no ID covers: add an ID in the same PR that records or
  fixes it, and answer it in every design doc. IDs are never deleted. One that no longer applies gets
  `(retired: <reason>)` in its text.
- **ID format:** `AREA-N`. N is the next free number in that area.

## LIFE — app lifecycle

| ID | Scenario | What must be true | Found by |
|---|---|---|---|
| LIFE-1 | Cold start: the state is read before its saved copy has loaded | Readers wait for it, or use a safe default they don't pin | FR1 matrix |
| LIFE-2 | First launch, nothing saved, no internet | The built-in default works; the next refresh still runs | FR1 matrix |
| LIFE-3 | App killed in the middle of a save | The old copy stays whole; the next save works (temp file + rename) | FR1 matrix |
| LIFE-4 | App killed mid-walk and relaunched | Nothing recorded is lost; unsent data is sent on launch; the walk resumes or ends cleanly | FR1 matrix, audit D1 |
| LIFE-5 | App in the background or screen off during a walk | Tracking, saving and sending carry on; timers and polls that aren't needed stop | audit (tracking) |
| LIFE-6 | Back to the app (resume) | State is checked again | FR1 matrix |
| LIFE-7 | App updated: new built-in data or new saved-file format | Old saved data still loads, or is migrated; a documented choice decides which copy wins | FR1 matrix |
| LIFE-8 | Saved data corrupt or the wrong shape | Ignored without a crash; falls back to a safe default | FR1 matrix |
| LIFE-9 | Two operations on the same state at once | One at a time; none lost; one owner of each file | FR1 matrix, audit D5 |
| LIFE-10 | App open for hours (tokens expire, timers pile up) | Keeps working after token expiry; timers don't stack | audit A6 |
| LIFE-11 | A start or setup step fails halfway | The app returns to a clean state, never stuck (e.g. "Recording" with nothing recording) | audit D3 |

## NET — network

| ID | Scenario | What must be true | Found by |
|---|---|---|---|
| NET-1 | Offline | The feature works offline or says clearly why not; nothing is lost | FR1 matrix, audit D8 |
| NET-2 | Server error (500, 503) | Current state kept; retried later | FR1 matrix |
| NET-3 | Request hangs (stuck socket, no reply) instead of failing | A bounded wait; a new request isn't blocked behind the stuck one | audit B4, A6 |
| NET-4 | Captive portal, or a 200 whose body can't be read | Treated as a failure; saved state untouched | FR1 matrix |
| NET-5 | Back online | Pending work is sent and state is refreshed | FR1 matrix, audit D1 |
| NET-6 | The server commits, but the reply is lost and the phone retries | The server treats the retry as the same request; nothing is counted twice | audit D6 |
| NET-7 | 401: token expired, or refresh failed offline | The request fails cleanly (never hangs); retried after sign-in; data kept | audit A6 |
| NET-8 | 403 / 404 | A clear message; no endless retry; no data deleted | audit E6 |
| NET-9 | 429 rate limit | Retried later; data kept | audit A7 |
| NET-10 | Any 4xx | Only a verdict about the data itself is final; everything else is retried; the phone never deletes user data because of a reply | audit A7 |

## AUTH — sign-in and accounts

| ID | Scenario | What must be true | Found by |
|---|---|---|---|
| AUTH-1 | Sign-out or account switch | Documented: what is kept, what is wiped; unsent data never goes to the wrong account and is never silently lost | FR1 matrix, audit D1 |
| AUTH-2 | Login | State is checked again for the new user | FR1 matrix |
| AUTH-3 | Account deleted, then a new sign-up (maybe within minutes) | No cache keeps the old id; the new account starts clean | audit A5 |
| AUTH-4 | Guest (no sign-in) | Works, or is documented as not supported until its FR | FR1 matrix |
| AUTH-5 | Forced sign-out mid-walk | The walk and its data are handled explicitly | audit (tracking) |
| AUTH-6 | A sign-in path that creates an account with no working login | Impossible: every account can sign in and be deleted | audit E1 |

## PRIV — privacy and data ownership

| ID | Scenario | What must be true | Found by |
|---|---|---|---|
| PRIV-1 | User A calls any endpoint with user B's id, or a list endpoint | Only the caller's own data is returned (0.x: single-player) | audit A1 |
| PRIV-2 | A real-time channel or hub | Sign-in required; broadcasts go only to people allowed to see them | audit A1 |
| PRIV-3 | Personal data in logs (coordinates, home, names) | Not logged, or coarsened | audit E4 |
| PRIV-4 | Delete account | No row with the user's id is left in any table, cache or identity provider (Firebase, Apple token revoked) | audit A4, E3 |
| PRIV-5 | Delete runs while a write for the same user is running | The write can't land after the delete (same lock) | audit A4 |

## DEV — the phone

| ID | Scenario | What must be true | Found by |
|---|---|---|---|
| DEV-1 | Permission denied, or denied forever | Explained, with a way to fix it; no sudden jump to Settings | audit (tracking) |
| DEV-2 | Permission revoked or GPS turned off mid-walk | Detected; the walk ends and is saved; the user is told why | audit D2 |
| DEV-3 | Approximate location only | Detected; the user is asked for precise location | audit D8 |
| DEV-4 | Notification permission denied (Android 13+, iOS) | Asked when needed; the feature degrades with a message | audit D8 |
| DEV-5 | Disk full while writing | The error is caught and shown; no half-written line spoils the next read | audit D4 |
| DEV-6 | Device clock changed, or a timestamp taken at the wrong moment | GPS fix time is used, not save time; the server doesn't trust the device clock blindly | audit A9 |
| DEV-7 | The OS kills background work (doze, battery optimisation) | Detected, or recovered from; the user is warned up front | audit D8 |
| DEV-8 | Battery drain (wake locks, polls, timers) | Only what the walk needs runs | audit (tracking) |
| DEV-9 | A fix with poor accuracy, including the very first fix | Filtered the same way everywhere | audit B2 |
| DEV-10 | GPS jump (multipath) or a burst of fixes arriving at once | Doesn't reject honest data or fake a speed | audit A7, A9 |

## IN — inputs, settings and config

| ID | Scenario | What must be true | Found by |
|---|---|---|---|
| IN-1 | NaN or ±Infinity in a setting or field | Rejected at the edge (startup, or the request) | audit B1 |
| IN-2 | 0 or negative | Rejected, or given a defined meaning | FR1 |
| IN-3 | Very large value, or a 10× typo | An upper bound rejects it | audit B5 |
| IN-4 | Missing field, null, or wrong type | Rejected as a whole, never half-applied | FR1 |
| IN-5 | Unknown extra field (a newer or older other side) | Ignored; deploy order documented | FR1 |
| IN-6 | A setting changed within its shipped range | Its effect is visible, and a test shows it at the shipped value and its neighbours | audit B3 |
| IN-7 | Settings that contradict each other (e.g. max hop vs speed × interval) | The validator checks the relation | audit (rules) |
| IN-8 | Bad config at startup | The server refuses to start; nothing that validates lazily is left to fail on first use | audit B1 |

## SRV — server and data

| ID | Scenario | What must be true | Found by |
|---|---|---|---|
| SRV-1 | Server redeployed mid-walk, or two versions running during a rolling deploy | A documented choice decides which version judges; the phone doesn't flip back and forth | FR1 matrix |
| SRV-2 | Phone and server versions differ (deploy order, rollback) | Both work, or the deploy order is written down | FR1 |
| SRV-3 | Two requests for the same user at once | Locked or idempotent; no lost update | audit A4, D6 |
| SRV-4 | Schema change, or startup code that rewrites data | Migration-managed; never deletes user data; a failed step stops startup | audit A2, E8 |
| SRV-5 | Seed or test data | Development only, never Production | audit A3 |
| SRV-6 | A huge input (polygon, path, batch) | Size checked before costly work; only the bad part is rejected | audit C6 |
| SRV-7 | Duplicate or replayed request | Detected (by id or content) | audit C3, D6 |
| SRV-8 | A total or counter | Derived from stored source data, or can be rebuilt from it; can't drift | audit E2, D6 |

## GAME — core game rules

| ID | Scenario | What must be true | Found by |
|---|---|---|---|
| GAME-1 | Figure-8 or other self-crossing path | Every simple loop counts | audit C1 |
| GAME-2 | A loop that ends on an earlier loop's edge | It counts | audit C2 |
| GAME-3 | Up one side of a street and back the other | Not a loop | audit C7 |
| GAME-4 | Standing still with GPS jitter | No path, distance or loop | audit (rules, tracking) |
| GAME-5 | A very large or very small loop | Its own limits apply; other loops are unaffected | audit C6 |
| GAME-6 | Paths that cross between two far-apart points | The crossing is detected | audit C9 |
| GAME-7 | Tracking gap (short or long) | Joined, or the loop restarts, as the spec says | audit D8 |
| GAME-8 | The step between two batches | Checked like any other step, and its distance is counted | audit C4, D6 |
| GAME-9 | Equal, backwards or zero-duration timestamps | Invalid, not treated as a default gap | audit C4 |
| GAME-10 | Too-fast section | Only that section is rejected; points are never deleted because of a verdict | audit A7 |
| GAME-11 | Trail vs loop; the unfinished last stretch | Only closed loops capture | audit C5 |
| GAME-12 | Exploration between points | Every hex the path crosses counts | audit C8 |
| GAME-13 | Phone preview vs server result | Same limits, same maths (earth radius, point caps), a replay test | audit A8, C10 |
| GAME-14 | End of walk | The result is always sent and queued, never skipped because the preview failed | audit A8 |

## CHEAT — anti-cheat

| ID | Scenario | What must be true | Found by |
|---|---|---|---|
| CHEAT-1 | A path or claim the phone sends that doesn't match the points the server received | The server judges only what it stored | audit C3 |
| CHEAT-2 | Spoofed timestamps | Capped against the server's receive time | audit C4 |
| CHEAT-3 | A teleport hidden inside a batch allowance, or split across gaps | Each step is checked on its own | audit C4 |
| CHEAT-4 | Driving under the speed cap | Covered by the spec's limit; the residual risk is accepted in writing | FR1, audit (capture) |
| CHEAT-5 | Replaying another walk | Detected | audit C3 |
| CHEAT-6 | Anti-cheat numbers reaching the phone or its messages | Never | FR1 |

## LEG — existing code and tests

| ID | Scenario | What must be true | Found by |
|---|---|---|---|
| LEG-1 | Old code in this area still runs and contradicts the version's scope | Listed; switched off or fixed by a named owner | audit A1, E5 |
| LEG-2 | Dead code, unreachable branches, comments that lie | Removed or corrected in the same PR | audit B8 |
| LEG-3 | A test that passes without guarding its claim (a fake at the wrong layer, a value outside the shipped range) | The fake sits at the lowest real layer; the test is proven red | audit A6, C11 |
| LEG-4 | Tests for code still running that aren't run in CI | They run in CI | audit D9 |
| LEG-5 | Places that should use this rule or state but don't (copies, bypasses, hard-coded numbers) | Found by grep and listed; each covered or owned | audit B2 (and rules: hard-coded numbers) |
| LEG-6 | Debug-only path reachable in release or profile builds | Gated with `kDebugMode` or an environment check | audit E6 |
| LEG-7 | Lessons in `docs/learnings/` and "Proposed" ADRs | Each is done, or has an owner | audit E8, E12 |
| LEG-8 | A test that waits in real time | Uses fake time and checks the exact limit, not a loose margin | audit B6 |
| LEG-9 | A check that CI runs more weakly than `scripts/verify.sh` (e.g. analyze warnings not failing) | CI enforces the same bar | audit E10 |
| LEG-10 | Architecture rule broken (a fat controller querying the DB, a module reaching into another's tables) | Fixed when that code is touched, or owned | audit E11 |
| LEG-11 | A file the docs call secret or ignored that is committed (e.g. Firebase config) | The docs and the repo agree; a real secret is never committed | audit E9 |

## API — contract between server and phone

| ID | Scenario | What must be true | Found by |
|---|---|---|---|
| API-1 | Field names, casing, types, units, time zones and ids (H3 as a string) | Match on both sides; a shared sample test; dates shown in local time | audit E7, D7 |
| API-2 | A constant duplicated on both sides | One source, or a test that fails on drift | audit (contracts) |
| API-3 | Contract tested only by serialising in the test | At least one test goes through the real HTTP pipeline | audit B7 |

## STORE — app stores

| ID | Scenario | What must be true | Found by |
|---|---|---|---|
| STORE-1 | App Store and Play rules: Sign in with Apple, account deletion, privacy manifest, permission purpose strings | Checked with `app-store-compliance` | audit E3, E12 |
