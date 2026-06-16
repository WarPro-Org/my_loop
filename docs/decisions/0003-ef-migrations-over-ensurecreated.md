# ADR-0003: Use EF Core Migrations, not EnsureCreated + raw ALTER

- **Status:** Proposed
- **Date:** 2026-06-11
- **Deciders:** Engineering

## Context

Startup currently calls `db.Database.EnsureCreated()` and then patches newly added
columns/tables with hand-written idempotent `ExecuteSqlRaw("ALTER TABLE ... IF NOT EXISTS")`
statements (the decay + exploration block in `Program.cs`). A single real EF migration also
exists on disk but is not applied this way.

`EnsureCreated()` and EF Migrations are **mutually exclusive**: `EnsureCreated` does not write
the `__EFMigrationsHistory` table, so migrations can never be cleanly adopted afterward. Every
future schema change then becomes a bespoke ALTER script. With 8+ active feature branches,
this diverges fast and risks data loss on fresh databases.

## Decision

Adopt **EF Core Migrations** as the single schema-evolution mechanism. Switch startup to
`db.Database.Migrate()`, remove the raw `ExecuteSqlRaw` ALTER hacks, and fold those
columns/tables into proper migrations. **Policy: every schema change ships as a new EF
migration, checked into git.**

## Consequences

- **Positive:** Deterministic, versioned schema across all machines and environments. Clean
  history; no per-machine drift; safe fresh-DB provisioning. Foundation for Phase 2/3 schema
  growth (seasons, clans, cosmetics).
- **Negative / Trade-offs:** One-time migration to reconcile databases originally created via
  `EnsureCreated` (baseline migration + mark as applied). Requires discipline: no more
  ad-hoc ALTERs.
- **Follow-ups:** See [runbooks/db-migrations.md](../runbooks/db-migrations.md) for the
  baseline-and-cutover procedure and the per-change workflow.

## Alternatives Considered

| Option | Why rejected |
|--------|--------------|
| Keep `EnsureCreated` + raw ALTERs | Unmanageable across branches; blocks ever adopting migrations; fresh-DB and data-loss risk. |
| Hand-managed SQL migration scripts (no EF) | Loses EF model/snapshot sync; duplicate source of truth for the schema. |
