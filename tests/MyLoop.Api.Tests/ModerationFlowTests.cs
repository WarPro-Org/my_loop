using System.Collections.Concurrent;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Models;
using MyLoop.Api.Options;
using MyLoop.Api.Services;
using MyLoop.Api.Services.Moderation;
using MyLoop.Api.Services.Moderation.Alerts;
using Testcontainers.PostgreSql;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// DR-002b / #190 — name reports, auto-hide and moderator decisions against real Postgres: the
/// flow depends on a row lock (FOR UPDATE), ON CONFLICT upserts and conditional updates, none of
/// which an in-memory provider reproduces.
/// </summary>
public class ModerationFlowTests : IAsyncLifetime
{
    private const string ModeratorUid = "uid-moderator";

    private readonly PostgreSqlContainer _pg = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    private string _conn = "";
    private readonly RecordingAlerts _alerts = new();

    private sealed class RecordingAlerts : IModerationAlerts
    {
        public ConcurrentQueue<ModerationAlert> Raised { get; } = new();
        public void Raise(ModerationAlert alert) => Raised.Enqueue(alert);
        public int Count(ModerationAlertKind kind) => Raised.Count(a => a.Kind == kind);
    }

    public async Task InitializeAsync()
    {
        await _pg.StartAsync();
        _conn = _pg.GetConnectionString();
        await using var db = NewDb();
        await db.Database.EnsureCreatedAsync();
    }

    public async Task DisposeAsync() => await _pg.DisposeAsync();

    private AppDbContext NewDb() =>
        new(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(_conn).Options);

    private static IModeratorDirectory Moderators()
    {
        var monitor = new Mock<IOptionsMonitor<ModerationOptions>>();
        monitor.Setup(m => m.CurrentValue).Returns(new ModerationOptions { ModeratorUids = [ModeratorUid] });
        return new ModeratorDirectory(monitor.Object);
    }

    private NameReportService Reports(AppDbContext db) =>
        new(db, Moderators(), _alerts, NullLogger<NameReportService>.Instance);

    private ModerationService Moderation(AppDbContext db) =>
        new(db, _alerts, NullLogger<ModerationService>.Instance);

    private async Task<Guid> SeedUser(string name, string? firebaseUid = null)
    {
        var id = Guid.NewGuid();
        await using var db = NewDb();
        db.Users.Add(new User { Id = id, FirebaseUid = firebaseUid ?? $"uid-{id}", DisplayName = name, Color = "#00D4AA" });
        await db.SaveChangesAsync();
        return id;
    }

    private async Task<List<Guid>> SeedUsers(int count)
    {
        var ids = new List<Guid>();
        for (var i = 0; i < count; i++) ids.Add(await SeedUser($"Reporter {i}"));
        return ids;
    }

    private async Task<NameReportOutcome> Report(Guid reporter, Guid target, NameReportReason reason = NameReportReason.Offensive)
    {
        await using var db = NewDb();
        return await Reports(db).ReportAsync(reporter, target, reason);
    }

    private async Task<User> LoadUser(Guid id)
    {
        await using var db = NewDb();
        return await db.Users.AsNoTracking().SingleAsync(u => u.Id == id);
    }

    private async Task<NameModerationCase> LoadCase(Guid userId)
    {
        await using var db = NewDb();
        return await db.NameModerationCases.AsNoTracking().SingleAsync(c => c.UserId == userId);
    }

    private async Task HideByReports(Guid target)
    {
        foreach (var reporter in await SeedUsers(GameConstantsThreshold))
            await Report(reporter, target);
    }

    private static int GameConstantsThreshold => MyLoop.Api.Constants.GameConstants.NameReportHideThreshold;

    // ---- Reports -------------------------------------------------------------------------

    [Fact]
    public async Task Threshold_reports_hide_the_name_and_alert_once_per_transition()
    {
        var target = await SeedUser("Rude Name");
        var reporters = await SeedUsers(GameConstantsThreshold);

        await Report(reporters[0], target);
        await Report(reporters[1], target);
        Assert.Equal("Rude Name", (await LoadUser(target)).DisplayName); // below threshold: still shown

        await Report(reporters[2], target);

        var user = await LoadUser(target);
        Assert.Equal(NameModeration.PlaceholderFor(target), user.DisplayName);
        Assert.NotNull(user.NameHiddenAt);
        var reviewCase = await LoadCase(target);
        Assert.Equal(ModerationCaseStatus.AutoHidden, reviewCase.Status);
        Assert.Equal("Rude Name", reviewCase.NameSnapshot);
        Assert.Equal(1, _alerts.Count(ModerationAlertKind.FirstReport));
        Assert.Equal(1, _alerts.Count(ModerationAlertKind.AutoHidden));
    }

    [Fact]
    public async Task Repeat_reports_by_one_player_count_once()
    {
        var target = await SeedUser("Rude Name");
        var reporter = (await SeedUsers(1))[0];

        Assert.Equal(NameReportOutcome.Accepted, await Report(reporter, target));
        Assert.Equal(NameReportOutcome.Ignored, await Report(reporter, target));
        Assert.Equal(NameReportOutcome.Ignored, await Report(reporter, target));

        await using var db = NewDb();
        Assert.Equal(1, await db.NameReports.CountAsync(r => r.ReportedUserId == target));
        Assert.Null((await LoadUser(target)).NameHiddenAt);
    }

    [Fact]
    public async Task Self_report_and_unknown_target_are_refused()
    {
        var player = await SeedUser("Robin");
        Assert.Equal(NameReportOutcome.SelfReport, await Report(player, player));
        Assert.Equal(NameReportOutcome.NotFound, await Report(player, Guid.NewGuid()));
    }

    [Fact]
    public async Task A_reporter_is_limited_per_day()
    {
        var reporter = await SeedUser("Reporter");
        var targets = await SeedUsers(MyLoop.Api.Constants.GameConstants.MaxNameReportsPerReporterPerDay + 1);

        for (var i = 0; i < targets.Count - 1; i++)
            Assert.Equal(NameReportOutcome.Accepted, await Report(reporter, targets[i]));

        Assert.Equal(NameReportOutcome.DailyLimitReached, await Report(reporter, targets[^1]));
    }

    [Fact]
    public async Task Reporting_a_moderator_is_silently_ignored()
    {
        var moderator = await SeedUser("Staff Person", ModeratorUid);
        foreach (var reporter in await SeedUsers(GameConstantsThreshold))
            Assert.Equal(NameReportOutcome.Ignored, await Report(reporter, moderator));

        Assert.Null((await LoadUser(moderator)).NameHiddenAt);
        await using var db = NewDb();
        Assert.False(await db.NameReports.AnyAsync(r => r.ReportedUserId == moderator));
    }

    [Fact]
    public async Task Concurrent_reports_hide_exactly_once()
    {
        var target = await SeedUser("Rude Name");
        var reporters = await SeedUsers(6);

        // Each report on its own context/connection, all at once — the FOR UPDATE lock must
        // serialise them so the threshold is neither missed nor crossed twice.
        await Task.WhenAll(reporters.Select(r => Report(r, target)));

        var user = await LoadUser(target);
        Assert.Equal(NameModeration.PlaceholderFor(target), user.DisplayName);
        Assert.Equal(1, _alerts.Count(ModerationAlertKind.FirstReport));
        Assert.Equal(1, _alerts.Count(ModerationAlertKind.AutoHidden));
        await using var db = NewDb();
        Assert.Equal(1, await db.NameModerationCases.CountAsync(c => c.UserId == target));
    }

    [Fact]
    public async Task A_hidden_name_accepts_no_further_reports()
    {
        var target = await SeedUser("Rude Name");
        await HideByReports(target);
        var late = (await SeedUsers(1))[0];

        Assert.Equal(NameReportOutcome.Ignored, await Report(late, target));
    }

    // ---- Moderator decisions -------------------------------------------------------------

    [Fact]
    public async Task Restore_writes_the_name_back_and_old_reports_do_not_rehide_it()
    {
        var target = await SeedUser("Kai Surname");
        await HideByReports(target);
        var caseId = (await LoadCase(target)).Id;

        await using (var db = NewDb())
            Assert.Equal(ModerationDecisionOutcome.Done, await Moderation(db).RestoreAsync(caseId, ModeratorUid));

        var user = await LoadUser(target);
        Assert.Equal("Kai Surname", user.DisplayName);
        Assert.Null(user.NameHiddenAt);
        Assert.Equal(ModerationCaseStatus.Restored, (await LoadCase(target)).Status);

        // One new report reopens the case; the three already-judged reports must not count.
        var newReporter = (await SeedUsers(1))[0];
        Assert.Equal(NameReportOutcome.Accepted, await Report(newReporter, target));
        Assert.Equal("Kai Surname", (await LoadUser(target)).DisplayName);
        Assert.Equal(ModerationCaseStatus.Open, (await LoadCase(target)).Status);
    }

    [Fact]
    public async Task Restore_after_the_player_renamed_keeps_the_new_name()
    {
        var target = await SeedUser("Rude Name");
        await HideByReports(target);
        await using (var db = NewDb())
            await new UserService(db, new ValidationService(), NullLogger<UserService>.Instance)
                .UpdateProfile(target, new UpdateUserRequest { DisplayName = "Nice Name" });

        await using (var db = NewDb())
            await Moderation(db).RestoreAsync((await LoadCase(target)).Id, ModeratorUid);

        var user = await LoadUser(target);
        Assert.Equal("Nice Name", user.DisplayName);
        Assert.Null(user.NameHiddenAt);
    }

    [Fact]
    public async Task Confirming_an_open_case_hides_the_name_and_two_strikes_lock_renaming()
    {
        var target = await SeedUser("First Bad");
        var reporter = (await SeedUsers(1))[0];
        await Report(reporter, target); // below threshold: case open, name visible

        await using (var db = NewDb())
            Assert.Equal(ModerationDecisionOutcome.Done,
                await Moderation(db).ConfirmAsync((await LoadCase(target)).Id, ModeratorUid));

        var afterFirst = await LoadUser(target);
        Assert.Equal(NameModeration.PlaceholderFor(target), afterFirst.DisplayName);
        Assert.Equal(1, afterFirst.ConfirmedNameStrikes);
        Assert.Null(afterFirst.NameLockedAt);

        // Second offence: rename, get hidden again, confirmed again → locked.
        await using (var db = NewDb())
            await new UserService(db, new ValidationService(), NullLogger<UserService>.Instance)
                .UpdateProfile(target, new UpdateUserRequest { DisplayName = "Second Bad" });
        await HideByReports(target);
        Guid secondCase;
        await using (var db = NewDb())
            secondCase = (await db.NameModerationCases.SingleAsync(c => c.UserId == target && c.NameSnapshot == "Second Bad")).Id;
        await using (var db = NewDb())
            await Moderation(db).ConfirmAsync(secondCase, ModeratorUid);

        var afterSecond = await LoadUser(target);
        Assert.Equal(2, afterSecond.ConfirmedNameStrikes);
        Assert.NotNull(afterSecond.NameLockedAt);

        await using (var db = NewDb())
        {
            Assert.True(await Moderation(db).IsConfirmedRemovedNameAsync(target, "Second Bad"));
            Assert.True(await Moderation(db).UnlockNameAsync(target));
        }
        Assert.Null((await LoadUser(target)).NameLockedAt);
    }

    [Fact]
    public async Task Decisions_are_idempotent_and_a_confirmed_case_cannot_be_restored()
    {
        var target = await SeedUser("Rude Name");
        await HideByReports(target);
        var caseId = (await LoadCase(target)).Id;

        await using var db = NewDb();
        var moderation = Moderation(db);
        Assert.Equal(ModerationDecisionOutcome.Done, await moderation.ConfirmAsync(caseId, ModeratorUid));
        Assert.Equal(ModerationDecisionOutcome.Done, await moderation.ConfirmAsync(caseId, ModeratorUid));
        Assert.Equal(ModerationDecisionOutcome.InvalidState, await moderation.RestoreAsync(caseId, ModeratorUid));
        Assert.Equal(ModerationDecisionOutcome.NotFound, await moderation.ConfirmAsync(Guid.NewGuid(), ModeratorUid));
        Assert.Equal(1, (await LoadUser(target)).ConfirmedNameStrikes); // the repeat confirm added nothing
    }

    [Fact]
    public async Task Case_queue_reports_count_and_reasons()
    {
        var target = await SeedUser("Rude Name");
        var reporters = await SeedUsers(2);
        await Report(reporters[0], target, NameReportReason.Offensive);
        await Report(reporters[1], target, NameReportReason.Impersonation);

        await using var db = NewDb();
        var cases = await Moderation(db).ListCasesAsync([ModerationCaseStatus.Open]);

        var entry = Assert.Single(cases);
        Assert.Equal("Rude Name", entry.NameSnapshot);
        Assert.Equal(2, entry.ReportCount);
        Assert.Equal(["offensive", "impersonation"], entry.Reasons.OrderByDescending(r => r).ToArray());
        Assert.Equal("open", entry.Status);
    }

    // ---- Rescan --------------------------------------------------------------------------

    [Fact]
    public async Task Rescan_hides_existing_blocked_names_once_and_respects_restored_decisions()
    {
        var offensive = await SeedUser("Hitler Fan");      // stored before the blocklist existed
        var restored = await SeedUser("Admin Smith");     // blocked, but a moderator will restore it
        var fine = await SeedUser("Robin");

        await using (var db = NewDb())
        {
            var first = await Moderation(db).RescanAsync(CancellationToken.None);
            Assert.Equal(2, first.Hidden);
        }
        Assert.Equal(NameModeration.PlaceholderFor(offensive), (await LoadUser(offensive)).DisplayName);
        Assert.Equal("Robin", (await LoadUser(fine)).DisplayName);
        Assert.Equal(ModerationCaseSource.Rescan, (await LoadCase(offensive)).Source);
        Assert.Equal(1, _alerts.Count(ModerationAlertKind.RescanDigest));

        await using (var db = NewDb())
            await Moderation(db).RestoreAsync((await LoadCase(restored)).Id, ModeratorUid);

        await using (var db = NewDb())
            Assert.Equal(0, (await Moderation(db).RescanAsync(CancellationToken.None)).Hidden);
        Assert.Equal("Admin Smith", (await LoadUser(restored)).DisplayName);
        Assert.Equal(1, _alerts.Count(ModerationAlertKind.RescanDigest)); // nothing hidden → no digest
    }

    // ---- Schema & lifecycle --------------------------------------------------------------

    [Fact]
    public async Task Schema_patch_upgrades_a_database_created_before_moderation()
    {
        await using (var db = NewDb())
        {
            // Recreate the pre-#190 shape: EnsureCreated made everything, so remove what the patch adds.
            await db.Database.ExecuteSqlRawAsync(@"
                DROP TABLE ""NameReports"";
                DROP TABLE ""NameModerationCases"";
                DROP TABLE ""UserBlocks"";
                ALTER TABLE ""Users"" DROP COLUMN ""NameHiddenAt"", DROP COLUMN ""ConfirmedNameStrikes"", DROP COLUMN ""NameLockedAt"";");
            DbInitializer.ApplyModerationSchema(db);
            DbInitializer.ApplyModerationSchema(db); // idempotent: a second startup is a no-op
        }

        var target = await SeedUser("Rude Name");
        await HideByReports(target);
        Assert.NotNull((await LoadUser(target)).NameHiddenAt);

        // The patch's foreign keys cascade exactly like the EF model's.
        await using (var db = NewDb())
            await db.Users.Where(u => u.Id == target).ExecuteDeleteAsync();
        await using (var db = NewDb())
        {
            Assert.False(await db.NameReports.AnyAsync(r => r.ReportedUserId == target));
            Assert.False(await db.NameModerationCases.AnyAsync(c => c.UserId == target));
        }

        // UserBlocks from the patch: insertable and cascading.
        var blocker = await SeedUser("Blocker");
        var blocked = await SeedUser("Blocked");
        await using (var db = NewDb())
            Assert.Equal(BlockOutcome.Done, await new BlockService(db).BlockAsync(blocker, blocked));
        await using (var db = NewDb())
            await db.Users.Where(u => u.Id == blocked).ExecuteDeleteAsync();
        await using (var db = NewDb())
            Assert.False(await db.UserBlocks.AnyAsync());
    }

    [Fact]
    public async Task Deleting_an_account_removes_its_reports_and_cases_both_ways()
    {
        var target = await SeedUser("Rude Name");
        var reporter = (await SeedUsers(1))[0];
        await Report(reporter, target);
        await Report(target, reporter);

        await using (var db = NewDb())
            Assert.True(await new UserService(db, new ValidationService(), NullLogger<UserService>.Instance).DeleteAccount(target));

        await using var check = NewDb();
        Assert.False(await check.NameReports.AnyAsync(r => r.ReporterId == target || r.ReportedUserId == target));
        Assert.False(await check.NameModerationCases.AnyAsync(c => c.UserId == target));
    }
}
