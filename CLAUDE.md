# MyLoop — CLAUDE.md

---

## Claude Conduct Rules (Hard Constraints)

These rules override all default Claude behavior. No exceptions.

1. **No supportive filler.** Never say "great idea", "good catch", "absolutely", "sounds good", or any positive affirmation. Omit them entirely.
2. **No false claims.** If confidence is not high, prefix the statement with `UNVERIFIED:`. For verified claims, cite the file path and line number. Never hallucinate library APIs, .NET internals, or Flutter behavior.
3. **Challenge every user proposal.** When the user proposes a design, solution, or code change — treat it as a hypothesis. Actively interrogate it for: race conditions, missed edge cases, cross-stack contract violations (.NET ↔ Flutter), security holes, performance regressions, and architectural debt. State specific objections with evidence. Do not implement a proposal that has unresolved issues.
4. **Counter-proposal obligation.** If Claude rejects or objects to a proposal, it must provide a concrete alternative. A bare rejection with no alternative is not acceptable.
5. **No sycophantic pivots.** If the user pushes back without new technical evidence, hold the position. Change stance only when given a concrete argument.
6. **No partial work.** Never leave a half-implemented fix or stub with a TODO unless the user explicitly agrees to it.

---

## Project Overview

MyLoop is a real-world GPS territory-capture game ("Pokémon GO meets Risk meets Strava"): a Flutter app and a
.NET 10 REST API. Players walk a closed loop outdoors to claim the H3 hexes inside it. Auth is Firebase JWT (Sign in
with Apple + Google). The multiplayer closed beta is being rebuilt as single-player version 0.1, one FR at a time
(`docs/versions/1/0.1/requirements.md`); old beta code (stealing, live map, leaderboard) stays until the FR that
replaces it.

```
my_loop/
  api/MyLoop.Api/        ← .NET 10 REST API host: controllers, old beta services, EF migrations, SignalR hubs
  api/MyLoop.Modules.*/  ← 0.1 modules, one class library each (e.g. Rules), used only through their interface
  mobile/                ← Flutter app (Dart)
  tests/                 ← MyLoop.V01.Tests (0.1, runs in CI), MyLoop.Api.Tests (old, compiled only), contracts/
  docs/                  ← all docs (see Docs map)
  scripts/               ← verify.sh and dev scripts
```

**Mobile stack:** Flutter, Riverpod (state), go_router (navigation), Dio (HTTP), Firebase Auth
**API stack:** .NET 10, Entity Framework (migrations in `api/MyLoop.Api/Migrations/`), SignalR (`Hubs/`)
**Auth:** Firebase JWT — the API validates the token on every request

---

## Docs map — what to read, when

All docs live under `docs/`; `docs/README.md` says what each folder holds. Read the docs for the activity before
starting it. "PR rules" fails a PR that adds a docs folder or a top-level docs file this map doesn't name.

| Activity | Read first |
|---|---|
| Planning a version or FR (Gate 1) | the version's `requirements.md` (`docs/versions/<release>/<version>/`), `docs/scenarios.md`, the records of earlier FRs (`records/`), `docs/decisions/` |
| Writing a design doc (Gate 2) | the above, plus `docs/architecture/`, `docs/data-removals.md` and the version's `audits/` |
| Coding (Gate 3) | the FR's design doc (`design/`), the records of FRs whose code it touches, `docs/architecture/`, `docs/runbooks/` for migrations and deploys |
| Reviewing | the task, the design doc, `docs/scenarios.md`, `docs/data-removals.md` |
| Fixing a bug | the version's `bugs/`, the records of the FRs it touches, `docs/scenarios.md`, `docs/data-removals.md` |
| Anything iOS-facing | `docs/compliance/` |
| Closing an FR | the version's `audits/` and `records/` |

**Before changing or fixing a file, find the FRs that own it:** search the records for the file's name, its name
without the extension (records often write `HexGridService`, not `HexGridService.cs`) and each folder above it
(e.g. `grep -rl -e game_rules_provider -e shared/rules/ docs/versions/*/*/records/`), and read every record that
matches, above all its "Decisions that must stay true". A change that breaks one of those is a change of plan: the
spec is updated first, and that record in the same PR.

Only for background: `docs/product/` (the beta's product spec and design log; `requirements.md` wins where they
disagree), `docs/design/` (beta design reviews), `docs/learnings/` (the story behind rules).

**A lesson counts only once it is something Claude reads anyway:** a rule in this file, a skill, a
`docs/scenarios.md` ID or a "PR rules" check, added in the PR that records the lesson. `docs/learnings/` keeps only
the story of why, so nothing there has to be read to follow the rules.

---

## Architecture Rules — SOLID, independent modules in one app

- **Always follow SOLID.**
- The API is **one deployable app made of independent modules** (e.g. Rules, Walks, Accounts, Areas) — not microservices.
- Each module is its own class-library project with a public interface. Other modules use only that interface — never
  its internal classes or its database tables.
- Controllers are thin: they call a module's interface and nothing else.
- Add an interface where there is a real second implementation or a test seam — not one per class.
- The Flutter app follows the same idea: features depend on abstractions (e.g. `ILocationSource`), not concrete plugins.

---
## How we work

**Chat style**
- Keep every response short, plain, and easy to read. No walls of text.
- One point and one question per turn. Wait for the answer before moving on.
- Discuss a requirement fully and get the user's agreement **before** any work on it starts.

**Spec-driven order**
- Requirements live in `docs/versions/<release>/<version>/requirements.md` (e.g. `docs/versions/1/0.1/`).
- Requirements are numbered FR1, FR2, … in build order. Work happens strictly in that order.
- The spec is updated first; code follows the spec. Any change of plan updates the spec before the code.
**Stay on the goal**
- Build only what the current FR needs. No settings, endpoints or code "for later" — each FR adds its own.
- Still design for extension (interfaces, modules, versioned data) so later FRs add code instead of rewriting it.
**Tests during the 0.x rebuild**
- The old test suites and coverage gates are paused in CI (the old test project is still compiled). CI runs the build,
  `flutter analyze`, CodeQL, and the 0.1 user-story tests (`tests/MyLoop.V01.Tests`, `mobile/test/v0_1`) once they exist.
- Each user story writes its own tests when it is finished. Those tests are added back to CI as they land.
  Exception: lifecycle-matrix tests (`state-lifecycle-consistency`) land in the same commit as the reader they cover.
- Where a gate below says run `dotnet test` / `flutter test`, run all 0.1 user-story tests plus build and `flutter analyze`.

**Requirement and design gates (SRDP).** Applies to every task — bugs, features, refactors and small changes. Never
skip a gate. Gate approval is the user saying anything like "yeah ok", "ok next", "looks good".
- **Bugs (2 gates):** a Bug Report the user approves before any code → the fix, regression tests, and `dotnet test`,
  `flutter test` and `flutter analyze` passing.
- **Features and refactors (3 gates):** Gate 1 requirement grill (one question at a time, through every
  `docs/scenarios.md` ID) → Gate 2 design doc `docs/versions/<release>/<version>/design/frN-<name>.md`, approved when
  the owner merges it → Gate 3 code matching the design, tests and the Pre-PR skills.

**Workflow skills — load the one for the step before doing it.** They hold the full procedures that used to live
here. They are not gate skills: they never go in the gate tables or a PR's "Skills run".

| Before … | Load |
|---|---|
| planning a requirement, writing a Bug Report or design doc, answering scenario IDs | `myloop-srdp-gates` |
| creating or updating a task, branching, opening, describing or merging a PR, stacked PRs | `myloop-tasks-and-prs` |
| reviewing a commit or PR (and in every reviewer agent's prompt) | `myloop-agent-review` |
| closing an FR, or changing something an earlier FR's record states | `myloop-closing-an-fr` |

---

## Branch & PR Workflow

- Branch format: FR work uses `v0.1/frN-<part>` (see Planning Chat & User Stories); everything else uses
  `{username}/{short-description}` (e.g. `ashukla/fix-login-flow`)
- **Never push directly to `master`** — branch protection is enforced
- All changes require a PR with at least 1 approval before merging
- Keep PRs focused — one concern per PR

---

## Gates are mandatory

The Pre-Check-in gate, the Pre-PR gate and the independent agent review run on **every** check-in and PR —
no exception, and no user instruction (e.g. "speed up", "just push it") bypasses them. If a gate cannot run,
stop and say so instead of checking in. The PR description lists every gate row that applies and the skill run for it.

**Only claim what ran.** A gate counts only if its skill was actually invoked on that exact commit. Never tick a
box or write "Skills run" from memory or the template. A gate done by hand is written as "by hand", not as the
skill. After a new commit, gates that depend on the code run again.

**Checklist — go through it every time** (the one list; details are in the workflow skills):

| Step | Before … | Must be true |
|---|---|---|
| 1 | writing FR code | Requirement agreed (Gate 1), including a pass through every `docs/scenarios.md` ID; design doc `docs/versions/<release>/<version>/design/frN-<name>.md` merged after the owner approved it (Gate 2) |
| 2 | each commit | Pre-Check-in skills that apply have run; the lifecycle matrix tests for readers this commit touches are in it |
| 3 | after each push | Linked items synced (`myloop-tasks-and-prs`); independent review of **this** commit, whose report ends with `REVIEWED <commit>`; findings fixed and the fix reviewed |
| 4 | opening a PR | A code PR has its `**Scenarios:**` line (IDs covered or changed, or `none — <reason>`); gate rows gone through **one by one** (`myloop-tasks-and-prs`); the skills that apply have run on the head commit; `scripts/verify.sh` passed on it (this is `verification-loop` for MyLoop); description names each, truthfully, and lists every review under `## Independent review` as `REVIEWED <commit> — <result>` |
| 5 | asking the owner to review / merging | Steps 1–4 hold on the current head commit; CI and "PR rules" green |
| 6 | calling an FR done | No `## Scenarios` row is `open` with this FR (`FRn`) or its task (`#N`) as owner; `myloop-closing-an-fr` steps 1–7 hold (final audit, record merged, spec, design doc, task, parent task, branches) |

"PR rules" (`.github/workflows/pr-rules.yml`) checks what a machine can: the gate section and skills, `REVIEWED`
for the latest commit, the Scenarios tables, the data-removal register, early blind audits, the Docs map and PR size.
What it enforces in full, and how to go through the gate rows: `myloop-tasks-and-prs`. **A missing or red "PR rules"
check counts as not passed.**

---

## Pre-Check-in Skill Gate

Before **committing** (check-in), run the skill(s) relevant to what the change touches.
These are fast, local, write-time skills — catch issues before they reach a PR.

| If the change touches… | Run before committing |
|------------------------|-----------------------|
| A disk-persisting / async-serialized service or its tests (`*queue*.dart`, `*cache*.dart`, WAL/offline queues, `mobile/test/**`) | `flutter-disk-concurrency-test` (stub `path_provider`, assert disk==memory + surviving set, prove the test fails without the fix) |
| **App state kept across launches or pinned for a walk, read by more than one place** (e.g. rules, saved profile, offline queues, values captured at walk start) | `state-lifecycle-consistency` (reader × app-moment matrix from the design doc (or the Bug Report on the bug track); tests for the readers this commit touches, through the real trigger; fake failures inside the real code, never its result; positive control before any "nothing happened" check; each test proven red when its behaviour is removed) |

A new skill gets a row in one of these two tables (Pre-Check-in for write-time checks, Pre-PR for review-time
ones), and a row with a file pattern also gets a line in `.github/gate-rows.tsv`, in the same PR.

---

## Pre-PR Skill Gate

Before opening **or** merging a PR, run the skill(s) relevant to what the PR touches.
This is a hard gate. Note in the PR description which skills were run.

Skills live in `.claude/skills/` (vendored from [ECC](https://github.com/affaan-m/ECC),
chosen from MyLoop's documented failure classes).

| If the PR touches… | Run before opening/merging |
|--------------------|----------------------------|
| **Any production C# or Dart code** | `coding-standards` (function size / no magic values / naming / comments / logging / exceptions), `solid-architecture` (SOLID, module boundaries, where constants, settings and interfaces belong) |
| .NET API code (Controllers / Services / Data) | `dotnet-patterns`, `csharp-testing` |
| Startup / DI / pipeline / `Program.cs` / `Configuration/*Extensions.cs` / Controllers | `webapi-standards` (keep `Program.cs` a thin composition root; group registrations; Options pattern; thin controllers) |
| DB schema / EF migrations / hex counts | `database-migrations` (verify atomicity + explicit transactions) |
| API endpoints or request/response shapes | `api-design` |
| **Anything crossing .NET ↔ Flutter** (DTOs, SignalR payloads, IDs, game constants) | `api-design` + **manually confirm field names, types (H3 CellId, UserId), and constants match on both sides** |
| Auth, anti-cheat, client-supplied coordinates, rate limits, secrets | `security-review` |
| SignalR / real-time / caches / offline queues | `latency-critical-systems` |
| **EF `EnableRetryOnFailure` / connection resilience / any explicit `BeginTransaction`** (`*DbContext*`, `Configuration/*Extensions.cs` DB wiring, services using transactions, Neon connection strings) | `database-retry-resilience` (wrap every explicit transaction in `CreateExecutionStrategy().ExecuteAsync`; idempotent block — `ChangeTracker.Clear()`, no additive-on-persistent-state writes; post-commit side effects outside the block; Npgsql `Timeout=` not `Connection Timeout=`) |
| Flutter / Dart code or Riverpod state | `dart-flutter-patterns`, `flutter-dart-code-review` |
| Background GPS / `location_service.dart` / `AndroidManifest.xml` / iOS `Info.plist` | `mobile-background-location` (verify foreground-service perms + iOS `UIBackgroundModes`) |
| **A mock/simulated/replayed GPS source or any client that submits walk paths** (`*mock*walk*`, `MockLocationService`, GPX/path replay, synthetic-path tests) | `mock-gps-anticheat` (jitter for bearing std-dev > 2°, real-time pacing, retained-point density ≥ minLoopPoints/minGpsPointsPerClaim, loop closure; environment-gate + logging-only for any honored mock flag) |
| **iOS-facing change** — auth/sign-in, location, push, permissions, data collected, account deletion, purchases, new SDK, `Info.plist` / `Runner.xcodeproj` / `PrivacyInfo.xcprivacy` | `app-store-compliance` (verify no App Store Review Guideline violation: SiwA 4.8, location 5.1.1/2.5.4, account deletion 5.1.1(v), privacy manifest) |
| Error/exception handling or offline durability | `error-handling` |
| **A PR that removes a method / endpoint / DTO / file** | `coordinate-overlapping-pr-removals` (grep open PRs for the deleted symbols — incl. their *tests*; decide + state merge order in both PRs; re-check overlapping PRs' mergeability after merging) |
| **Always — final gate** | `verification-loop`, run as `scripts/verify.sh` (build, 0.1 user-story tests, analyze with no new issues, secrets scan) + the independent agent review |

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

**Release and profile builds MUST pass the API host** — there is no fallback outside debug, and a
build without it shows a "Build misconfigured" screen instead of calling an unintended host:

```bash
flutter build apk --release --dart-define=API_URL=https://your-api-host
flutter build ipa --release --dart-define=API_URL=https://your-api-host
```

Debug builds fall back to a dev tunnel, so plain `flutter run` needs no flags.

---

## Key Conventions

### Flutter / Dart
- State management: Riverpod only — no raw setState for business logic
- Routing: go_router — all routes defined centrally in `lib/app/`
- Feature structure: `lib/features/{feature}/` — each feature owns its own screens, providers, and widgets
- HTTP: Dio client via shared service — never call `http` directly
- No hardcoded strings — use constants

### .NET API
- New 0.1 logic goes in a module (Architecture Rules); controllers stay in `Controllers/` and call the module's
  interface. Old beta code keeps Controller → `Services/` → `Data/` until the FR that rebuilds it
- Add EF migrations for any schema changes: `dotnet ef migrations add <Name>`
- Never commit secrets — use `appsettings.Development.json` (gitignored) for local config

### General
- No commented-out code committed to master
- PR description must explain the "why", not just the "what"
- Run tests before opening a PR

---

## CI

GitHub Actions runs on every PR:
- .NET 10 build of the API and every test project
- Flutter analysis
- CodeQL
- During the 0.x rebuild only the 0.1 user-story tests run, once they exist (see "Tests during the 0.x rebuild")

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
