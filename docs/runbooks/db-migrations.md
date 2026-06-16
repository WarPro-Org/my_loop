# Runbook: Database Migrations

Policy (see [ADR-0003](../decisions/0003-ef-migrations-over-ensurecreated.md)): **every
schema change ships as a new EF Core migration, checked into git.** No `EnsureCreated`, no
ad-hoc `ALTER TABLE` in `Program.cs`.

## Per-change workflow

```bash
# From api/MyLoop.Api
dotnet ef migrations add <DescriptiveName>     # generates migration + snapshot
dotnet ef database update                       # apply locally
# review the generated Up()/Down(); commit migration + snapshot together
```

Startup applies pending migrations automatically via `db.Database.Migrate()`.

## One-time cutover from EnsureCreated

The schema was originally created with `EnsureCreated()`, which does **not** record a
migrations history. To adopt migrations on an existing database without recreating it:

1. Ensure the EF model matches the live schema (including the decay/exploration columns
   currently added via raw SQL).
2. Generate a baseline migration:
   ```bash
   dotnet ef migrations add Baseline
   ```
3. On each existing database, mark the baseline as already applied **without running it**:
   ```bash
   dotnet ef database update Baseline --connection "<conn>"   # only on a fresh DB
   # For existing DBs that already have the schema, insert the baseline row into
   # __EFMigrationsHistory instead of running Up(), so the schema isn't recreated.
   ```
4. Replace `EnsureCreated()` + the `ExecuteSqlRaw` ALTER block in `Program.cs` with
   `db.Database.Migrate()`.
5. From here on, every change follows the per-change workflow above.

> **Warning:** do not run a baseline `Up()` against a database that already has the tables —
> it will fail or duplicate objects. The baseline is a no-op recording step for existing DBs.

## Rollback

`dotnet ef database update <PreviousMigrationName>` runs the `Down()` migrations. Always
review `Down()` before relying on it; destructive `Down()` steps should be reviewed in PR.
