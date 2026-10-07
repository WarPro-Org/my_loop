# Phase 1 — Learnings

Running, reverse-chronological log of non-obvious discoveries during Phase 1. One entry per
discovery. Keep it skimmable: what surprised us, the fix, and how to apply it next time.

---

## 2026-10-07 — "Always follow SOLID" had no check

**Surprise:** CLAUDE.md said "Always follow SOLID", but no gate skill covered it: `coding-standards` checks
function size, names and magic numbers, and `dotnet-patterns` checks C# idioms. The author also ran every skill
alone; the reviewer read the diff but not the skills' checklists.
**Fix:** a `solid-architecture` skill (SOLID, module boundaries, where constants, settings and interfaces belong),
required by "PR rules" for any production C# or Dart file, and the independent reviewer now works through the
checklist of every gate skill the PR lists.
**Apply next time:** a rule in CLAUDE.md that no skill or check enforces is a wish; give it one.

## 2026-10-07 — FR1 kept reopening: edge cases were hunted only after the code was done

**Surprise:** FR1 (game rules) was closed, then a blind audit and the new scenario catalogue found about 30 gaps,
and fixing them kept finding more. The reviews had only checked each change against its task ("does it do what it
says"), never "what can go wrong". So nobody asked what happens with a 403 or 429 reply, a typo of 500 instead of
50, `Infinity`, or a setting that does nothing at its shipped value (`Loop:SkipNeighbors`) or contradicts another
(the 60 m hop limit against speed × interval + drift). And every finding was pulled back into FR1, even when the
code belonged to a later FR that rewrites it anyway.
**Fix:** (1) An early blind audit before each design doc is reviewed (CLAUDE.md Gate 2, checked by "PR rules"), so
these cases are found before the code. (2) After an FR's final audit, findings are triaged once and the FR's list
is frozen: only gaps in the FR's own code that break its own spec stay; the rest go to the FR that owns that code
(CLAUDE.md "Closing an FR"). The scenario catalogue (`docs/scenarios.md`) keeps the cases for every later FR.
**Apply next time:** Hunt for failure cases before the design is approved, not after the FR is closed; and send a
finding to the FR that owns the code, not to whichever FR is open.

## 2026-06-11 — EnsureCreated() silently blocks future EF migrations

**Surprise:** `db.Database.EnsureCreated()` never writes `__EFMigrationsHistory`, so EF
`Migrate()` can't adopt the schema later. New columns were being patched in with raw
idempotent `ALTER TABLE ... IF NOT EXISTS` in `Program.cs` — unmanageable across branches.
**Fix:** Adopt EF Migrations; switch startup to `Migrate()`; fold raw ALTERs into a baseline
migration. See [ADR-0003](../decisions/0003-ef-migrations-over-ensurecreated.md) and
[runbook](../runbooks/db-migrations.md).
**Apply next time:** Default new services to `Migrate()` from the first commit.

## 2026-06-11 — README claimed PostGIS/GiST that the code doesn't use

**Surprise:** The README advertised a "PostGIS GiST spatial index," but geometry is stored as
JSON strings and viewport queries use `CenterLat`/`CenterLng` range scans. NetTopologySuite is
only used in-memory for polygon fill. The real spatial index is the H3 parent buckets
(`ParentCellId`, `NeighborhoodId`).
**Fix:** Documented the true model in
[spatial-model.md](../architecture/spatial-model.md) and [ADR-0001](../decisions/0001-h3-over-postgis.md);
README to be corrected.
**Apply next time:** Docs describe what the code does, not the aspiration. Correct the README
in the same PR as the architectural choice.

## 2026-06-11 — Missing iOS Privacy Manifest = guaranteed rejection

**Surprise:** No `PrivacyInfo.xcprivacy` exists. Firebase / geolocator / path_provider use
required-reason APIs, so Apple auto-rejects (ITMS-91053) without it.
**Fix:** Author the manifest before archiving — see
[privacy-manifest.md](../compliance/privacy-manifest.md).
**Apply next time:** Add the privacy manifest the moment a required-reason SDK is introduced,
not at submission time.
