using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Constants;
using MyLoop.Api.Data.Seeding;

namespace MyLoop.Api.Data;

/// <summary>
/// Startup database bootstrap: ensure the schema exists, apply idempotent patches for columns and
/// tables added after the initial create, seed bootstrap data, and keep today's leaderboard current.
/// </summary>
/// <remarks>
/// The raw idempotent DDL below is retained verbatim from the previous inline startup block because
/// the app uses <c>EnsureCreated()</c> rather than EF migrations. Switching to migrations is tracked
/// separately (ADR-0003) and is intentionally out of scope here.
/// </remarks>
public static class DbInitializer
{
    public static async Task InitializeDatabaseAsync(this WebApplication app)
    {
        using var scope = app.Services.CreateScope();
        var services = scope.ServiceProvider;
        var logger = services.GetRequiredService<ILoggerFactory>().CreateLogger(nameof(DbInitializer));
        var db = services.GetRequiredService<AppDbContext>();

        db.Database.EnsureCreated();
        ApplySchemaPatches(db, services.GetRequiredService<IHexGridService>(), logger);

        await DatabaseSeeder.SeedAsync(db, logger);
        DatabaseSeeder.EnsureTodayLeaderboard(db);
    }

    internal static void ApplySchemaPatches(AppDbContext db, IHexGridService hexGrid, ILogger logger)
    {
        // The DDL is idempotent (IF NOT EXISTS) because EnsureCreated won't add columns/tables to an
        // existing database. A throw here is unlikely to be a benign "already exists" — surface it
        // instead of swallowing a real schema failure.
        try
        {
            ApplyExplorationSchema(db);
            BackfillExploredCells(db, hexGrid);
            ApplyXpSchema(db);
            ApplyDecayAndMissionsSchema(db);
            ApplyAchievementsSchema(db);
            ApplyTerritoryIndexes(db);
            ApplyNeighborhoodNamesSchema(db);
            // Last on purpose: adding the stored DecayAt column rewrites TerritoryCells under
            // an ACCESS EXCLUSIVE lock, the heaviest and likeliest-to-fail step. Running it
            // last means a failure here cannot skip the cheaper patches above.
            ApplyDecayReleaseSchema(db);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex,
                "Startup schema sync failed (continuing; later queries may break if this was a real error)");
        }

        // Separate from the block above so a failure here is loud and attributable: the moderation
        // endpoints would otherwise surface it only as 500s long after startup.
        try
        {
            ApplyModerationSchema(db);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Moderation schema patch failed; name reports and moderation will not work");
        }
    }

    private static void ApplyExplorationSchema(AppDbContext db)
    {
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"TerritoryCells\" ADD COLUMN IF NOT EXISTS \"LastRefreshedAt\" timestamp with time zone NOT NULL DEFAULT NOW()");
        db.Database.ExecuteSqlRaw(@"
            CREATE TABLE IF NOT EXISTS ""ExploredCells"" (
                ""UserId"" uuid NOT NULL,
                ""CellId"" bigint NOT NULL,
                ""NeighborhoodId"" bigint NOT NULL,
                ""FirstVisitedAt"" timestamp with time zone NOT NULL,
                CONSTRAINT ""PK_ExploredCells"" PRIMARY KEY (""UserId"", ""CellId"")
            )");
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_ExploredCells_UserId_NeighborhoodId""
            ON ""ExploredCells"" (""UserId"", ""NeighborhoodId"")");
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_ExploredCells_NeighborhoodId""
            ON ""ExploredCells"" (""NeighborhoodId"")");
    }

    // Backfill ExploredCells from TerritoryCells for any cells captured before ExploredCells tracking
    // was added — computing the correct res-8 neighborhood for each.
    private static void BackfillExploredCells(AppDbContext db, IHexGridService hexGrid)
    {
        var unbackfilled = db.Database.SqlQueryRaw<long>(
            @"SELECT t.""CellId"" FROM ""TerritoryCells"" t
              WHERE NOT EXISTS (
                  SELECT 1 FROM ""ExploredCells"" e
                  WHERE e.""UserId"" = t.""OwnerId"" AND e.""CellId"" = t.""CellId""
              )").ToList();
        if (unbackfilled.Count == 0)
            return;

        // Also fix any existing rows that used the wrong parent resolution.
        db.Database.ExecuteSqlRaw(@"DELETE FROM ""ExploredCells""");

        var cells = db.TerritoryCells.AsNoTracking()
            .Select(t => new { t.CellId, t.OwnerId, t.ClaimedAt })
            .ToList();
        foreach (var batch in cells.Chunk(500))
        {
            foreach (var c in batch)
            {
                var neighborhoodId = hexGrid.GetNeighborhoodId(c.CellId);
                db.Database.ExecuteSqlRaw(
                    @"INSERT INTO ""ExploredCells"" (""UserId"", ""CellId"", ""NeighborhoodId"", ""FirstVisitedAt"")
                      VALUES ({0}, {1}, {2}, {3})
                      ON CONFLICT (""UserId"", ""CellId"") DO NOTHING",
                    c.OwnerId, c.CellId, neighborhoodId, c.ClaimedAt);
            }
        }
    }

    private static void ApplyXpSchema(AppDbContext db)
    {
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"TotalXp\" bigint NOT NULL DEFAULT 0");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"Level\" integer NOT NULL DEFAULT 1");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"TotalHexesStolen\" integer NOT NULL DEFAULT 0");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"AllMissionsCompleteDays\" integer NOT NULL DEFAULT 0");
    }

    private static void ApplyDecayAndMissionsSchema(AppDbContext db)
    {
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"TerritoryCells\" ADD COLUMN IF NOT EXISTS \"DecayDays\" integer NOT NULL DEFAULT 7");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"HomeLat\" double precision");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"HomeLng\" double precision");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"HomeCity\" text NOT NULL DEFAULT ''");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"HomeState\" text NOT NULL DEFAULT ''");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"HomeCountry\" text NOT NULL DEFAULT ''");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"HomeContinent\" text NOT NULL DEFAULT ''");
        // Home-change cooldown gate (anti-cheat, #84). Left NULL for existing rows so
        // accounts that set home before this column existed get one tracked change.
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"HomeSetAt\" timestamp with time zone");
        db.Database.ExecuteSqlRaw(@"
            CREATE TABLE IF NOT EXISTS ""DailyMissions"" (
                ""Id"" uuid NOT NULL,
                ""UserId"" uuid NOT NULL,
                ""Date"" date NOT NULL,
                ""Type"" integer NOT NULL,
                ""TargetValue"" integer NOT NULL,
                ""CurrentProgress"" integer NOT NULL DEFAULT 0,
                ""XpReward"" integer NOT NULL,
                ""CompletedAt"" timestamp with time zone,
                ""Description"" text NOT NULL DEFAULT '',
                CONSTRAINT ""PK_DailyMissions"" PRIMARY KEY (""Id"")
            )");
        ApplyDailyMissionUniqueIndexPatch(db);
    }

    /// <summary>
    /// One mission per type per user-day (#131). The old non-unique (UserId, Date) index let two
    /// concurrent first-of-day generations both insert, yielding 6 missions and double XP surface.
    /// Collapses any existing duplicates (keeping the row with the most progress, then the lowest
    /// Id) before swapping the index, so the unique create can't fail. Idempotent — safe to run
    /// on every startup and on fresh databases where EnsureCreated already built the unique index.
    /// </summary>
    internal static void ApplyDailyMissionUniqueIndexPatch(AppDbContext db)
    {
        db.Database.ExecuteSqlRaw(@"
            DELETE FROM ""DailyMissions"" d
            USING ""DailyMissions"" k
            WHERE d.""UserId"" = k.""UserId""
              AND d.""Date"" = k.""Date""
              AND d.""Type"" = k.""Type""
              AND d.""Id"" <> k.""Id""
              AND (d.""CurrentProgress"" < k.""CurrentProgress""
                   OR (d.""CurrentProgress"" = k.""CurrentProgress"" AND d.""Id"" > k.""Id""))");
        db.Database.ExecuteSqlRaw(
            @"DROP INDEX IF EXISTS ""IX_DailyMissions_UserId_Date""");
        db.Database.ExecuteSqlRaw(@"
            CREATE UNIQUE INDEX IF NOT EXISTS ""IX_DailyMissions_UserId_Date_Type""
            ON ""DailyMissions"" (""UserId"", ""Date"", ""Type"")");
    }

    private static void ApplyAchievementsSchema(AppDbContext db)
    {
        db.Database.ExecuteSqlRaw(@"
            CREATE TABLE IF NOT EXISTS ""UserAchievements"" (
                ""Id"" uuid NOT NULL,
                ""UserId"" uuid NOT NULL,
                ""AchievementId"" text NOT NULL,
                ""UnlockedAt"" timestamp with time zone NOT NULL,
                ""XpAwarded"" integer NOT NULL DEFAULT 0,
                CONSTRAINT ""PK_UserAchievements"" PRIMARY KEY (""Id"")
            )");
        db.Database.ExecuteSqlRaw(@"
            CREATE UNIQUE INDEX IF NOT EXISTS ""IX_UserAchievements_UserId_AchievementId""
            ON ""UserAchievements"" (""UserId"", ""AchievementId"")");
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_UserAchievements_UserId""
            ON ""UserAchievements"" (""UserId"")");
    }

    internal static void ApplyTerritoryIndexes(AppDbContext db)
    {
        // NeighborhoodId on TerritoryCells for per-area ownership queries.
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"TerritoryCells\" ADD COLUMN IF NOT EXISTS \"NeighborhoodId\" bigint NOT NULL DEFAULT 0");
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_TerritoryCells_OwnerId_NeighborhoodId""
            ON ""TerritoryCells"" (""OwnerId"", ""NeighborhoodId"")");

        // BRIN index for viewport spatial queries (much faster than B-tree for range scans).
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_TerritoryCells_Geo_Brin""
            ON ""TerritoryCells"" USING BRIN (""CenterLat"", ""CenterLng"")
            WITH (pages_per_range = 128)");

        // Bucket-first viewport query (#114): prune by res-3 parent, refine by center.
        // The composite's prefix covers the old single-column ParentCellId index, so drop it.
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_TerritoryCells_ParentCellId_CenterLat_CenterLng""
            ON ""TerritoryCells"" (""ParentCellId"", ""CenterLat"", ""CenterLng"")");
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_TerritoryCells_ParentCellId_OwnerId""
            ON ""TerritoryCells"" (""ParentCellId"", ""OwnerId"")");
        db.Database.ExecuteSqlRaw(
            @"DROP INDEX IF EXISTS ""IX_TerritoryCells_ParentCellId""");

        // Daily claim-cap count + claim-history grouping both filter Claims by
        // (UserId, CreatedAt); the cap check runs inside EVERY claim transaction (#124).
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_Claims_UserId_CreatedAt""
            ON ""Claims"" (""UserId"", ""CreatedAt"")");
    }

    // Persisted, shared-across-all-users reverse-geocode cache (#121 / ML-ERR-024) — lets
    // /game-state's exploration stats return without ever awaiting Nominatim inline.
    /// <summary>
    /// Name moderation schema (DR-002b, #190) for databases created before it. One transaction —
    /// Postgres DDL is transactional, so a failure leaves no half-applied schema. Additive only
    /// (defaulted/nullable columns, new tables), so the previous build keeps working against it.
    /// Must produce the same shape as AppDbContext's NameReport/NameModerationCase configuration.
    /// </summary>
    internal static void ApplyModerationSchema(AppDbContext db)
    {
        // EnableRetryOnFailure rejects bare user transactions; the DDL is idempotent, so a retry
        // of the whole block is safe.
        db.Database.CreateExecutionStrategy().Execute(() =>
        {
            using var tx = db.Database.BeginTransaction();
            db.Database.ExecuteSqlRaw(ModerationSchemaDdl);
            tx.Commit();
        });
    }

    private static readonly string ModerationSchemaDdl = $@"
            ALTER TABLE ""Users"" ADD COLUMN IF NOT EXISTS ""NameHiddenAt"" timestamp with time zone NULL;
            ALTER TABLE ""Users"" ADD COLUMN IF NOT EXISTS ""ConfirmedNameStrikes"" integer NOT NULL DEFAULT 0;
            ALTER TABLE ""Users"" ADD COLUMN IF NOT EXISTS ""NameLockedAt"" timestamp with time zone NULL;

            CREATE TABLE IF NOT EXISTS ""NameReports"" (
                ""Id"" uuid NOT NULL,
                ""ReporterId"" uuid NOT NULL,
                ""ReportedUserId"" uuid NOT NULL,
                ""NameSnapshot"" character varying({GameConstants.MaxModeratedNameLength}) NOT NULL,
                ""Reason"" smallint NOT NULL,
                ""CreatedAt"" timestamp with time zone NOT NULL,
                CONSTRAINT ""PK_NameReports"" PRIMARY KEY (""Id""),
                CONSTRAINT ""FK_NameReports_Users_ReporterId"" FOREIGN KEY (""ReporterId"") REFERENCES ""Users"" (""Id"") ON DELETE CASCADE,
                CONSTRAINT ""FK_NameReports_Users_ReportedUserId"" FOREIGN KEY (""ReportedUserId"") REFERENCES ""Users"" (""Id"") ON DELETE CASCADE
            );
            CREATE UNIQUE INDEX IF NOT EXISTS ""IX_NameReports_ReporterId_ReportedUserId_NameSnapshot""
                ON ""NameReports"" (""ReporterId"", ""ReportedUserId"", ""NameSnapshot"");
            CREATE INDEX IF NOT EXISTS ""IX_NameReports_ReportedUserId_NameSnapshot_CreatedAt""
                ON ""NameReports"" (""ReportedUserId"", ""NameSnapshot"", ""CreatedAt"");
            CREATE INDEX IF NOT EXISTS ""IX_NameReports_ReporterId_CreatedAt""
                ON ""NameReports"" (""ReporterId"", ""CreatedAt"");

            CREATE TABLE IF NOT EXISTS ""NameModerationCases"" (
                ""Id"" uuid NOT NULL,
                ""UserId"" uuid NOT NULL,
                ""NameSnapshot"" character varying({GameConstants.MaxModeratedNameLength}) NOT NULL,
                ""Source"" smallint NOT NULL,
                ""Status"" smallint NOT NULL,
                ""OpenedAt"" timestamp with time zone NOT NULL,
                ""HiddenAt"" timestamp with time zone NULL,
                ""ResolvedAt"" timestamp with time zone NULL,
                ""ResolvedByUid"" character varying({GameConstants.MaxFirebaseUidLength}) NULL,
                CONSTRAINT ""PK_NameModerationCases"" PRIMARY KEY (""Id""),
                CONSTRAINT ""FK_NameModerationCases_Users_UserId"" FOREIGN KEY (""UserId"") REFERENCES ""Users"" (""Id"") ON DELETE CASCADE
            );
            CREATE UNIQUE INDEX IF NOT EXISTS ""IX_NameModerationCases_UserId_NameSnapshot""
                ON ""NameModerationCases"" (""UserId"", ""NameSnapshot"");
            CREATE INDEX IF NOT EXISTS ""IX_NameModerationCases_Status""
                ON ""NameModerationCases"" (""Status"");";

    private static void ApplyNeighborhoodNamesSchema(AppDbContext db)
    {
        db.Database.ExecuteSqlRaw(@"
            CREATE TABLE IF NOT EXISTS ""NeighborhoodNames"" (
                ""NeighborhoodId"" bigint NOT NULL,
                ""AreaName"" text NOT NULL,
                ""ResolvedAt"" timestamp with time zone NOT NULL,
                CONSTRAINT ""PK_NeighborhoodNames"" PRIMARY KEY (""NeighborhoodId"")
            )");
    }

    /// <summary>
    /// Decay-release schema (#104): the CellTransfer Reason audit column, and the stored
    /// DecayAt generated column + index that make the hourly reaper scan indexable
    /// (the old per-row interval predicate forced a full-table scan; its helper index
    /// on (LastRefreshedAt, DecayDays) never served the predicate and is dropped).
    /// Nothing may CREATE that old index any more: a non-concurrent build takes a SHARE
    /// lock that blocks claim writes, and rebuilding it only to drop it here would repeat
    /// on every cold start. The DROP stays so existing databases are cleaned up.
    /// Idempotent — safe on every startup and on fresh EnsureCreated databases.
    /// </summary>
    internal static void ApplyDecayReleaseSchema(AppDbContext db)
    {
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"CellTransfers\" ADD COLUMN IF NOT EXISTS \"Reason\" integer NOT NULL DEFAULT 0");
        db.Database.ExecuteSqlRaw(@"
            ALTER TABLE ""TerritoryCells"" ADD COLUMN IF NOT EXISTS ""DecayAt"" timestamp without time zone
            GENERATED ALWAYS AS ((""LastRefreshedAt"" AT TIME ZONE 'UTC') + make_interval(days => ""DecayDays"")) STORED");
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_TerritoryCells_DecayAt""
            ON ""TerritoryCells"" (""DecayAt"")");
        db.Database.ExecuteSqlRaw(
            @"DROP INDEX IF EXISTS ""IX_TerritoryCells_Decay""");
    }
}
