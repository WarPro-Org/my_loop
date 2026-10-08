---
name: myloop-srdp-gates
description: MyLoop's requirement and design gates in full: the bug track (Bug Report sections, fix and verification) and the feature track (Gate 1 requirement grill, Gate 2 design doc sections including Scenarios table and early blind audit, Gate 3 implementation), plus the scenario catalogue rules (docs/scenarios.md, [search] IDs, data-removal register). Use before planning a requirement, writing a Bug Report or design doc, or answering scenario IDs.
origin: MyLoop (moved from CLAUDE.md to keep it small)
---

# Requirement and design gates (SRDP) and the scenario catalogue

Moved word for word from CLAUDE.md, which keeps a one-paragraph summary.

## Socratic Requirement & Design Protocol (SRDP)

**Applies to every task — bugs, features, refactors, and small changes. Never skip a gate. Gate approval is signalled by the user saying anything like "yeah ok", "ok next", "this seems ok", "looks good", etc.**

---

### Bugs → Lightweight Track (2 gates)

#### Bug Gate 1 — Bug Report Doc (before touching any code)

Produce a Bug Report covering:
- **Symptom:** What is observed vs. what is expected.
- **Reproduction steps:** Exact sequence to trigger the bug.
- **Root cause hypothesis:** Where in the code the fault likely lives, and why. Cite file paths.
- **Blast radius:** What else could break if this area is changed.
- **Fix plan:** The proposed change in plain English — no code yet.
- **Lifecycle matrix rows** (if the bug is in state covered by `state-lifecycle-consistency`): the affected rows,
  each with the test that will prove it. On the bug track this report is the matrix's home.

Do not write code until the user approves the Bug Report.

#### Bug Gate 2 — Implementation + Verification

- Implement the fix exactly as described in the approved Bug Report. Any deviation must be called out before committing.
- Write regression tests that would have caught this bug.
- Run: `dotnet test` (API), `flutter test` (mobile), `flutter analyze` (mobile).
- Gate does not close until all three pass.

---

### Features & Refactors → Full Track (3 gates)

#### Gate 1 — Requirement Grill (loop until approved)

Role: strict Senior PM + Software Architect. Do not write code or design docs.

Interrogate the request on:
- Edge cases and failure modes
- Offline durability and retry behaviour
- Battery and GPS constraints (mobile)
- Security and anti-cheat surface
- .NET ↔ Flutter contract boundaries (field names, types, H3 CellId, UserId, game constants)
- Concurrency and race conditions
- EF migration atomicity
- Every ID in `docs/scenarios.md`: say which apply to this requirement; a question no ID covers becomes a new ID

Ask one sharp question at a time. Do not advance until requirements are unambiguous and the user approves.

#### Gate 2 — Design Document (loop until approved)

Write a Design Doc only after Gate 1 is approved. Must include:

- **API changes:** Exact endpoint paths, HTTP verbs, request/response DTOs with field names and types.
- **DB schema changes:** Table/column changes and the EF migration plan, including rollback strategy.
- **SignalR changes:** Hub method names and payload shapes.
- **Riverpod state impact:** Which providers change, what they hold, how they are invalidated.
- **Cross-stack contract table:** Side-by-side field name + type mapping for every .NET ↔ Flutter boundary touched.
- **Known risk checklist:** Race conditions, offline edge cases, anti-cheat gaps — each either mitigated or explicitly accepted.
- **Lifecycle matrix** (for state covered by `state-lifecycle-consistency`): every reader × every app moment, each with its test or
  an agreed "accepted" — see `state-lifecycle-consistency`.
- **`## Scenarios` table:** every ID in `docs/scenarios.md`, each `covered` (test file in backticks and the test's
  name in double quotes), `n/a` (reason), `open` (owner FR or task) or `accepted` (where the owner approved it). "PR rules" fails when an ID is missing.
- **`## Early blind audit`:** before the design doc goes to review, 2–3 agents are given only the requirement and the
  code it builds on (never the draft design) and each searches one area for every way it can go wrong: failure
  replies, bad and extreme values, settings that do nothing or contradict each other, hard-coded numbers. Every
  finding becomes a `docs/scenarios.md` ID (or a row under one) and a row in the `## Scenarios` table. The report is
  saved in `docs/versions/<release>/<version>/audits/` and this section links it; "PR rules" fails a new design doc
  without it. The blind audit at close-out then only checks what this pass missed.

Do not write implementation code until the user explicitly approves the Design Doc. The doc lives at
`docs/versions/<release>/<version>/design/frN-<name>.md`; approval = the owner merges its PR into master. If the user proposes an alternative design, critique it against the approved Gate 1 requirements before accepting it.

#### Gate 3 — Implementation + Verification

- Write production code matching the approved Design Doc exactly. Call out any deviation before committing.
- Write comprehensive tests: unit, integration, and widget tests as appropriate.
- Run: `dotnet test` (API), `flutter test` (mobile), `flutter analyze` (mobile).
- Run all relevant Pre-PR skills from the skill gate table below.
- Gate does not close until tests are green, lint is clean, and skills are run.

## Scenario catalogue

**Scenario catalogue (`docs/scenarios.md`)** — the one list of every edge case. "PR rules" checks it on every PR.
- **Look it up every time:**
  - planning a requirement (Gate 1), going through every ID;
  - the design doc (Gate 2), whose `## Scenarios` table answers every ID;
  - each code PR, whose `**Scenarios:**` line names the IDs it covers or changes;
  - every review, which checks the PR against those IDs;
  - closing an FR, when no row of its table is left `open` with that FR (`FRn`) or its task (`#N`) as owner.
- **`n/a` on an existing-code ID needs a search:** an ID marked `[search]` is about code that already exists. Answer
  `n/a` only after searching the whole code base, written as `searched: <what> — <result>`. "My change doesn't do
  this" is not an answer. "PR rules" checks the prefix; the reviewer checks the search was real.
- **Data-removal register (`docs/data-removals.md`, DATA-1):** every file that deletes, overwrites, hands over or
  expires user data is listed with a verdict (`keeps #N` or `breaks #N` plus an owner). A PR that adds such code adds
  its row in the same PR.
- **Keep it growing without being asked:** any finding that no ID covers (a review, audit, bug, test failure or
  user report) becomes a new ID in the PR that records or fixes it. The same PR answers the new ID in every design
  doc. IDs are never deleted.
- A planning or design agent that isn't sure whether an ID applies marks it `open` with an owner, never `n/a`.
