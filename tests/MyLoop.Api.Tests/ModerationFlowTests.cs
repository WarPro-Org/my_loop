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
/// flow depends on a row lock (FOR NO KEY UPDATE), ON CONFLICT upserts and conditional updates, none of
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

    private static IModeratorDirectory Moderators(params string[] uids)
    {
        var monitor = new Mock<IOptionsMonitor<ModerationOptions>>();
        monitor.Setup(m => m.CurrentValue).Returns(new ModerationOptions { ModeratorUids = uids });
        return new ModeratorDirectory(monitor.Object);
    }

    private NameReportService Reports(AppDbContext db, bool withModerator = true) =>
        new(db, withModerator ? Moderators(ModeratorUid) : Moderators(), _alerts, NullLogger<NameReportService>.Instance);

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

    private static UserService Users(AppDbContext db) =>
        new(db, new ValidationService(), NullLogger<UserService>.Instance);

    private async Task<ProfileUpdateStatus> Rename(Guid userId, string name)
    {
        await using var db = NewDb();
        return (await Users(db).UpdateProfile(userId, new UpdateUserRequest { DisplayName = name })).Status;
    }

    /// <summary>Puts a hidden name back on show behind moderation's back ("hide undone somehow").</summary>
    private async Task UndoHide(Guid userId, string name)
    {
        await using var db = NewDb();
        await db.Users.Where(u => u.Id == userId).ExecuteUpdateAsync(s => s
            .SetProperty(u => u.DisplayName, name)
            .SetProperty(u => u.NameHiddenAt, (DateTime?)null));
    }

    /// <summary>
    /// Runs a rename while another transaction holds the player's row lock — the position a report,
    /// confirm or rescan is in part-way through. <paramref name="concurrentWork"/> runs in that
    /// transaction once the rename is waiting behind it, then commits.
    /// </summary>
    private async Task<ProfileUpdateStatus> RenameAgainst(Guid userId, string name, Func<AppDbContext, Task> concurrentWork)
    {
        await using var other = NewDb();
        await using var tx = await other.Database.BeginTransactionAsync();
        await ModerationLocks.LockUserAsync(other, userId);

        var rename = Rename(userId, name);
        await WaitForALockWaiter();
        await concurrentWork(other);
        await tx.CommitAsync();
        return await rename;
    }

    private async Task WaitForALockWaiter()
    {
        await using var db = NewDb();
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (DateTime.UtcNow < deadline)
        {
            var waiting = await db.Database
                .SqlQueryRaw<int>(@"SELECT count(*)::int AS ""Value"" FROM pg_locks WHERE NOT granted")
                .ToListAsync();
            if (waiting[0] > 0) return;
            await Task.Delay(20);
        }
        throw new TimeoutException("The rename never waited on the held row lock");
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
        Assert.False(await db.NameModerationCases.AnyAsync(c => c.UserId == moderator));
        Assert.Empty(await Moderation(db).ListCasesAsync([ModerationCaseStatus.Open, ModerationCaseStatus.AutoHidden]));
        // Recorded, so each one spent its reporter's daily budget like any other report.
        Assert.Equal(GameConstantsThreshold, await db.NameReports.CountAsync(r => r.ReportedUserId == moderator));
        Assert.Empty(_alerts.Raised);
    }

    [Fact]
    public async Task Reporting_a_moderator_spends_the_daily_budget_like_any_report()
    {
        // The probe: at limit - 1, report a candidate, then a fresh player. If the candidate's report
        // cost nothing, the second report is accepted and the candidate is exposed as a moderator.
        var reporter = await SeedUser("Reporter");
        foreach (var target in await SeedUsers(MyLoop.Api.Constants.GameConstants.MaxNameReportsPerReporterPerDay - 1))
            Assert.Equal(NameReportOutcome.Accepted, await Report(reporter, target));
        var moderator = await SeedUser("Staff Person", ModeratorUid);
        var player = (await SeedUsers(1))[0];

        Assert.Equal(NameReportOutcome.Ignored, await Report(reporter, moderator));
        Assert.Equal(NameReportOutcome.DailyLimitReached, await Report(reporter, player));
    }

    [Fact]
    public async Task Reports_filed_while_a_player_moderated_never_count_after_they_stop()
    {
        var formerModerator = await SeedUser("Staff Person", ModeratorUid);
        foreach (var reporter in await SeedUsers(GameConstantsThreshold))
            await Report(reporter, formerModerator);

        // Removed from the allowlist: one new report opens a case, and the earlier reports are
        // outside its window, so the name is not hidden and the queue shows one report.
        var newReporter = (await SeedUsers(1))[0];
        await using (var db = NewDb())
            Assert.Equal(NameReportOutcome.Accepted,
                await Reports(db, withModerator: false).ReportAsync(newReporter, formerModerator, NameReportReason.Other));

        Assert.Equal("Staff Person", (await LoadUser(formerModerator)).DisplayName);
        await using var check = NewDb();
        var entry = Assert.Single(await Moderation(check).ListCasesAsync([ModerationCaseStatus.Open]));
        Assert.Equal(1, entry.ReportCount);
    }

    [Fact]
    public async Task Concurrent_reports_hide_exactly_once()
    {
        var target = await SeedUser("Rude Name");
        var reporters = await SeedUsers(6);

        // Each report on its own context/connection, all at once — the row lock must
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
    public async Task Two_players_reporting_each_other_at_once_do_not_deadlock()
    {
        // Each report locks its target's row, and its NameReports insert takes a foreign-key
        // KEY SHARE lock on the reporter's row. With FOR UPDATE those two conflict, so A→B racing
        // B→A deadlocked (40P01); this context has no retrying strategy to hide that.
        for (var round = 0; round < 5; round++)
        {
            var pair = await SeedUsers(2);
            var outcomes = await Task.WhenAll(Report(pair[0], pair[1]), Report(pair[1], pair[0]));
            Assert.All(outcomes, o => Assert.Equal(NameReportOutcome.Accepted, o));
        }
    }

    [Fact]
    public async Task A_hidden_name_accepts_no_further_reports()
    {
        var target = await SeedUser("Rude Name");
        await HideByReports(target);
        var late = (await SeedUsers(1))[0];

        Assert.Equal(NameReportOutcome.Ignored, await Report(late, target));
    }

    // ---- #194 review regressions ---------------------------------------------------------

    [Fact]
    public async Task Renaming_straight_back_to_an_auto_hidden_name_is_refused()
    {
        var target = await SeedUser("Rude Name");
        await HideByReports(target);

        Assert.Equal(ProfileUpdateStatus.NameRemoved, await Rename(target, "Rude Name"));
        Assert.Equal(NameModeration.PlaceholderFor(target), (await LoadUser(target)).DisplayName);
        Assert.Equal(ProfileUpdateStatus.Updated, await Rename(target, "Nice Name"));
    }

    [Fact]
    public async Task At_the_daily_limit_a_moderator_answers_like_everyone_else()
    {
        var reporter = await SeedUser("Reporter");
        foreach (var target in await SeedUsers(MyLoop.Api.Constants.GameConstants.MaxNameReportsPerReporterPerDay))
            await Report(reporter, target);
        var moderator = await SeedUser("Staff Person", ModeratorUid);
        var player = (await SeedUsers(1))[0];

        Assert.Equal(NameReportOutcome.DailyLimitReached, await Report(reporter, player));
        Assert.Equal(NameReportOutcome.DailyLimitReached, await Report(reporter, moderator));
    }

    [Fact]
    public async Task Restoring_an_older_case_does_not_undo_a_newer_hide()
    {
        var target = await SeedUser("Bad One");
        await HideByReports(target);
        var olderCase = (await LoadCase(target)).Id;
        Assert.Equal(ProfileUpdateStatus.Updated, await Rename(target, "Bad Two"));
        await HideByReports(target);

        await using (var db = NewDb())
            await Moderation(db).RestoreAsync(olderCase, ModeratorUid);

        var user = await LoadUser(target);
        Assert.Equal(NameModeration.PlaceholderFor(target), user.DisplayName); // "Bad Two" stays hidden
        Assert.NotNull(user.NameHiddenAt);
    }

    [Fact]
    public async Task A_rename_saved_after_a_concurrent_hide_clears_the_hidden_flag()
    {
        var target = await SeedUser("Rude Name");
        await using var renameContext = NewDb();
        // The rename's context has already loaded the user (NameHiddenAt = null) when the hide commits.
        Assert.NotNull(await renameContext.Users.FindAsync(target));
        await HideByReports(target);

        await Users(renameContext).UpdateProfile(target, new UpdateUserRequest { DisplayName = "Nice Name" });

        var user = await LoadUser(target);
        Assert.Equal("Nice Name", user.DisplayName);
        Assert.Null(user.NameHiddenAt); // otherwise every later report of "Nice Name" would be ignored
    }

    // ---- #194 review round 2 -------------------------------------------------------------

    [Fact]
    public async Task A_confirm_committing_while_a_rename_is_checked_blocks_the_confirmed_name()
    {
        var target = await SeedUser("Bad Name");
        await Report((await SeedUsers(1))[0], target); // case Open, name still showing
        Assert.Equal(ProfileUpdateStatus.Updated, await Rename(target, "Other Name"));
        var caseId = (await LoadCase(target)).Id;

        // The player renames back to "Bad Name" while a moderator's confirm is part-way through.
        // The rename used to check (case Open → allowed) before the confirm committed, then save
        // "Bad Name" under a Confirmed case that nothing could hide again.
        var outcome = await RenameAgainst(target, "Bad Name", other =>
            other.NameModerationCases.Where(c => c.Id == caseId)
                .ExecuteUpdateAsync(s => s.SetProperty(c => c.Status, ModerationCaseStatus.Confirmed)));

        Assert.Equal(ProfileUpdateStatus.NameRemoved, outcome);
        Assert.Equal("Other Name", (await LoadUser(target)).DisplayName);
    }

    [Fact]
    public async Task Resaving_an_unchanged_name_while_a_hide_commits_keeps_it_hidden()
    {
        var target = await SeedUser("Rude Name");
        var reporters = await SeedUsers(GameConstantsThreshold);
        for (var i = 0; i < GameConstantsThreshold - 1; i++) await Report(reporters[i], target);

        // A profile save resends the current name while the threshold report is part-way through.
        // It used to write only NameHiddenAt = NULL (DisplayName looked unchanged to EF), leaving
        // the placeholder showing with no hide flag, which no moderator could then restore.
        var outcome = await RenameAgainst(target, "Rude Name", async other =>
        {
            var now = DateTime.UtcNow;
            Assert.True(await NameHiding.HideAsync(other, target, "Rude Name", now));
            await other.NameModerationCases.Where(c => c.UserId == target).ExecuteUpdateAsync(s => s
                .SetProperty(c => c.Status, ModerationCaseStatus.AutoHidden)
                .SetProperty(c => c.HiddenAt, now));
        });

        Assert.Equal(ProfileUpdateStatus.NameRemoved, outcome);
        var user = await LoadUser(target);
        Assert.Equal(NameModeration.PlaceholderFor(target), user.DisplayName);
        Assert.NotNull(user.NameHiddenAt);
        await using (var db = NewDb())
            Assert.Equal(ModerationDecisionOutcome.Done, await Moderation(db).RestoreAsync((await LoadCase(target)).Id, ModeratorUid));
        Assert.Equal("Rude Name", (await LoadUser(target)).DisplayName); // restore still works
    }

    [Fact]
    public async Task Resaving_an_unchanged_name_after_a_hide_is_refused()
    {
        var target = await SeedUser("Rude Name");
        await using var renameContext = NewDb();
        Assert.NotNull(await renameContext.Users.FindAsync(target)); // loaded before the hide
        await HideByReports(target);

        var result = await Users(renameContext).UpdateProfile(target, new UpdateUserRequest { DisplayName = "Rude Name" });

        Assert.Equal(ProfileUpdateStatus.NameRemoved, result.Status);
        var user = await LoadUser(target);
        Assert.Equal(NameModeration.PlaceholderFor(target), user.DisplayName);
        Assert.NotNull(user.NameHiddenAt);
    }

    [Fact]
    public async Task Renaming_back_to_a_hidden_name_in_another_letter_case_is_refused()
    {
        var target = await SeedUser("Rude Name");
        await HideByReports(target);

        Assert.Equal(ProfileUpdateStatus.NameRemoved, await Rename(target, "rude name"));
        Assert.Equal(ProfileUpdateStatus.NameRemoved, await Rename(target, "RUDE NAME"));
        Assert.Equal(NameModeration.PlaceholderFor(target), (await LoadUser(target)).DisplayName);
    }

    [Fact]
    public async Task Renaming_back_to_a_hidden_name_stored_before_normalisation_is_refused()
    {
        // Stored before #189 with a smart apostrophe; a rename request is normalised to U+0027.
        var target = await SeedUser("Bad’Name");
        await HideByReports(target);

        Assert.Equal(ProfileUpdateStatus.NameRemoved, await Rename(target, "Bad'Name"));
    }

    [Fact]
    public async Task Confirm_hides_a_name_showing_under_an_auto_hidden_case()
    {
        var target = await SeedUser("Rude Name");
        await HideByReports(target);
        await UndoHide(target, "Rude Name");

        await using (var db = NewDb())
            Assert.Equal(ModerationDecisionOutcome.Done, await Moderation(db).ConfirmAsync((await LoadCase(target)).Id, ModeratorUid));

        var user = await LoadUser(target);
        Assert.Equal(NameModeration.PlaceholderFor(target), user.DisplayName);
        Assert.Equal(1, user.ConfirmedNameStrikes);
        var reviewCase = await LoadCase(target);
        Assert.Equal(ModerationCaseStatus.Confirmed, reviewCase.Status);
        Assert.Equal(user.NameHiddenAt, reviewCase.HiddenAt);
    }

    [Fact]
    public async Task A_report_rehides_a_name_showing_under_an_auto_hidden_case()
    {
        var target = await SeedUser("Rude Name");
        await HideByReports(target);
        await UndoHide(target, "Rude Name");

        Assert.Equal(NameReportOutcome.Accepted, await Report((await SeedUsers(1))[0], target));

        var user = await LoadUser(target);
        Assert.Equal(NameModeration.PlaceholderFor(target), user.DisplayName);
        Assert.NotNull(user.NameHiddenAt);
        var reviewCase = await LoadCase(target);
        Assert.Equal(ModerationCaseStatus.AutoHidden, reviewCase.Status);
        Assert.Equal(user.NameHiddenAt, reviewCase.HiddenAt);
        Assert.Equal(2, _alerts.Count(ModerationAlertKind.AutoHidden));
    }

    [Fact]
    public async Task A_name_showing_under_a_confirmed_case_is_hidden_again_without_a_second_strike()
    {
        var target = await SeedUser("Rude Name");
        await HideByReports(target);
        var caseId = (await LoadCase(target)).Id;
        await using (var db = NewDb())
            await Moderation(db).ConfirmAsync(caseId, ModeratorUid);

        // A repeat confirm re-applies the hide.
        await UndoHide(target, "Rude Name");
        await using (var db = NewDb())
            Assert.Equal(ModerationDecisionOutcome.Done, await Moderation(db).ConfirmAsync(caseId, ModeratorUid));
        Assert.Equal(NameModeration.PlaceholderFor(target), (await LoadUser(target)).DisplayName);

        // So does a report, and the case keeps its Confirmed status (and so can't be "restored").
        await UndoHide(target, "Rude Name");
        Assert.Equal(NameReportOutcome.Accepted, await Report((await SeedUsers(1))[0], target));

        var user = await LoadUser(target);
        Assert.Equal(NameModeration.PlaceholderFor(target), user.DisplayName);
        Assert.Equal(1, user.ConfirmedNameStrikes);
        Assert.Equal(ModerationCaseStatus.Confirmed, (await LoadCase(target)).Status);
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
        Assert.Equal(ProfileUpdateStatus.Updated, await Rename(target, "Nice Name"));

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
        Assert.Equal(ProfileUpdateStatus.Updated, await Rename(target, "Second Bad"));
        await HideByReports(target);
        Guid secondCase;
        await using (var db = NewDb())
            secondCase = (await db.NameModerationCases.SingleAsync(c => c.UserId == target && c.NameSnapshot == "Second Bad")).Id;
        await using (var db = NewDb())
            await Moderation(db).ConfirmAsync(secondCase, ModeratorUid);

        var afterSecond = await LoadUser(target);
        Assert.Equal(2, afterSecond.ConfirmedNameStrikes);
        Assert.NotNull(afterSecond.NameLockedAt);

        Assert.Equal(ProfileUpdateStatus.NameLocked, await Rename(target, "Anything"));
        await using (var db = NewDb())
            Assert.True(await Moderation(db).UnlockNameAsync(target));
        Assert.Null((await LoadUser(target)).NameLockedAt);

        // Unlocked, the player may rename — but not back to a name a moderator removed.
        Assert.Equal(ProfileUpdateStatus.NameRemoved, await Rename(target, "Second Bad"));
        Assert.Equal(ProfileUpdateStatus.Updated, await Rename(target, "Fresh Name"));
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
    }

    [Fact]
    public async Task Deleting_an_account_removes_its_reports_and_cases_both_ways()
    {
        var target = await SeedUser("Rude Name");
        var reporter = (await SeedUsers(1))[0];
        await Report(reporter, target);
        await Report(target, reporter);

        await using (var db = NewDb())
            Assert.True(await Users(db).DeleteAccount(target));

        await using var check = NewDb();
        Assert.False(await check.NameReports.AnyAsync(r => r.ReporterId == target || r.ReportedUserId == target));
        Assert.False(await check.NameModerationCases.AnyAsync(c => c.UserId == target));
    }
}
