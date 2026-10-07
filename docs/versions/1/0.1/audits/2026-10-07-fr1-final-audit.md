# FR1 (game rules) — final audit, 2026-10-07

- **Commit:** `c058acf` (master).
- **Scope:** "Closing an FR" step 1, final audit only:
  - FR1's spec section, and the bullets FR1 moved to FR3, FR5, FR6, FR7, FR8, FR9, FR12 and FR13;
  - task #201 and the parent task #198;
  - the 14 FR1 PRs;
  - the design doc, with its matrix and `## Scenarios` table;
  - the record;
  - the tests on master.
- **Blind audit not rerun:** owner decision. The 2026-09-29 blind audit (`2026-09-29-independent-audit.md`) already
  ran on FR1, its findings are fixed or moved to later FRs, and the FR1 list is frozen (2026-10-07, #229). A new blind
  audit could only feed later FRs, which run their own early blind audit (CLAUDE.md Gate 2).
- **Method:** an independent agent, which did not edit the repo; its red checks ran in a scratch worktree.

## Findings

No blockers. Seven minor findings, all in docs and tasks. The code and tests match what the docs claim. Each is
fixed in the close-out PR #231 or in task #201 at close-out step 4.

1. **The record was out of date.**
   - Its Status line listed PRs up to #220 and said rows were open.
   - "Tests that guard it" lacked the HTTP contract test, the refused and stuck-request tests and the exact-3 s
     walk-start tests.
   - "Left to later FRs" lacked the rows moved to FR6 (LEG-1), FR7 (SRV-4), FR8 (GAME-13) and FR13 (SRV-5).

   Fixed in #231.
2. **A spec line was false.** "Every setting has an upper limit at most 5× its shipped value" doesn't hold:
   `MaxSpeedViolationRate` is capped at 1, which is 20× its shipped 0.05, and `Version` has no limit. Reworded in #231.
3. **GAME-13 (open, owner FR8) was missing from FR8's spec section.** It is the 500-point preview cap against the
   server's 10,000, and different earth radii. Bullet added in #231.
4. **The design doc was stale in four places:**
   - the header and PR list;
   - the startup-check paragraph (no upper limits, `NaN`/`Infinity` or `RulesStartupCheck`);
   - the contract-test risk row (it still said "not the real HTTP pipeline");
   - no section on the work after the blind audit.

   Fixed in #231.
5. **Task #201's criteria notes were stale:**
   - the gaps since fixed (IN-1, IN-3, IN-8, NET-3, LIFE-10, NET-7) were still listed;
   - the "each setting has a changing-it test" box needs "except `SkipNeighbors` (FR6)";
   - the build box cites an old commit;
   - the Summary still said "reopened".

   Fixed at close-out step 4.
6. **#201's check-in log named commit hashes that aren't on master.** #229 and #230 were rebase-merged, so master
   holds copies under new hashes: `b80f69e` to `599c9be` for #229, and `023abcf` and `c058acf` for #230. Fixed at
   close-out step 4.
7. **The spec status line still said "reopened".** Set to done in #231 (close-out step 3).

## Acceptance criteria in #201

All are met by code and tests on master. The one unticked box is "no `## Scenarios` row open with #201". It is met:
no row has FR1 or #201 as owner, after #228 (rows moved), #229 (server rows) and #230 (phone rows).

## Checked and true

- **Spec, FR1 section:**
  - the 3 s walk-start wait (`walkStartRulesWait`) and the 30 s request limit, sign-in token step included;
  - refused replies keep the rules and the saved copy, and are never retried on their own;
  - limits are finite, and `NaN` and `Infinity` are rejected;
  - the server reads the rules only through `IRuleSettings`, and `AntiCheatConstants.cs` is gone.
- **Moved bullets:** FR3, FR5, FR6, FR7, FR9, FR12 and FR13 each mention their rows. FR8 did not (finding 3).
- **Values:** `appsettings.json`, the validator limits, the ETag format `{Version}-{16 hex}` and `client_rules.json`
  match the record.
- **Design doc:** its 101 scenario IDs equal the catalogue's 101, with none twice, and every `covered` row names an
  existing file and existing test names.
- **Open rows:** none has FR1 or #201 as owner. The owners in `docs/data-removals.md` agree.
- **Linked items:** PR states and merge commits match across #201, #198 and the PRs:
  - #203 `e868eca`, #210 `382107d`, #204 `a0c9725`, #205 `8a2d29e`, #214 `6d55b37`;
  - #215 `78830ae`, #216 `d65993e`, #218 `f38d33a`, #219 `18893ec`, #220 `26121e0`;
  - #222 `e05cf1d`, #228 `f7731cc`, #229 `599c9be`, #230 `c058acf`.
- **Task lines:** every commit from #228 to #230 has one.

## Red checks

Each broken in a scratch worktree at `c058acf`, then restored.

| Group | Break | Result |
|---|---|---|
| Server rules validation | dropped `&& value <= max` | 11 failures (over-limit cases and `Infinity`) |
| Server HTTP contract | `RulesController` never returns 304 | 2 failures (`RulesHttpTests`, `RulesControllerTests`) |
| Phone refused replies | rethrow `DioException` in refresh | about 14 failures (400–503, captive portal, offline, 401 then login) |
| Phone stuck request | removed `.timeout(rulesRequestLimit)` | the stuck-request test fails |
| Phone walk-start timing | `walkStartRulesWait` set to 4 s | both walk-start limit tests fail |
| Phone saved copy | save writes straight to the file (no temp + rename) | the cut-off-save test fails |

## Test totals on master

- `dotnet test tests/MyLoop.V01.Tests`: 102 passed, 0 failed.
- `flutter test test/v0_1 test/mock_walk_engine_test.dart`: 115 passed, 0 failed.
- `flutter analyze`: 20 issues, equal to the baseline in `scripts/verify.sh`, so none new.
