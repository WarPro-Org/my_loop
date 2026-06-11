# Phase 1 — Learnings

Running, reverse-chronological log of non-obvious discoveries during Phase 1. One entry per
discovery. Keep it skimmable: what surprised us, the fix, and how to apply it next time.

---

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
