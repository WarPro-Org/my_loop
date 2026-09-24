using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Constants;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Services.Moderation.Alerts;

namespace MyLoop.Api.Services.Moderation;

/// <summary>
/// Records name reports and auto-hides a name once <see cref="GameConstants.NameReportHideThreshold"/>
/// distinct players have reported it in the current review window (DR-002b, #190).
/// </summary>
public sealed class NameReportService(
    AppDbContext db,
    IModeratorDirectory moderators,
    IModerationAlerts alerts,
    ILogger<NameReportService> logger) : INameReportService
{
    /// <summary>What the transaction decided; alerts are raised from it after commit.</summary>
    private sealed record ReportResult(
        NameReportOutcome Outcome,
        Guid CaseId = default,
        string Name = "",
        int ReportCount = 0,
        bool CaseOpenedNow = false,
        bool HiddenNow = false);

    public async Task<NameReportOutcome> ReportAsync(Guid reporterId, Guid reportedUserId, NameReportReason reason)
    {
        if (reporterId == reportedUserId) return NameReportOutcome.SelfReport;

        var target = await db.Users.AsNoTracking()
            .Where(u => u.Id == reportedUserId)
            .Select(u => new { u.FirebaseUid })
            .SingleOrDefaultAsync();
        if (target is null) return NameReportOutcome.NotFound;
        // The limit is checked before the moderator test: otherwise, at the limit, every target
        // would answer 429 except a moderator (204), revealing who moderates (#194 review).
        if (await CountReportsTodayAsync(reporterId, DateTime.UtcNow) >= GameConstants.MaxNameReportsPerReporterPerDay)
            return NameReportOutcome.DailyLimitReached;
        // Answered exactly like an accepted report, so the endpoint never reveals who moderates.
        if (moderators.IsModerator(target.FirebaseUid)) return NameReportOutcome.Ignored;

        // EnableRetryOnFailure requires explicit transactions to run inside the execution strategy.
        // The block is idempotent: a retry after an ambiguous commit re-hits ON CONFLICT and
        // returns Ignored, so side effects below can never run twice.
        var result = await db.Database.CreateExecutionStrategy()
            .ExecuteAsync(() => RecordReportAsync(reporterId, reportedUserId, reason));

        // Post-commit, outside the retried block (database-retry-resilience).
        if (result.CaseOpenedNow)
            alerts.Raise(ModerationAlert.ForCase(ModerationAlertKind.FirstReport, result.CaseId, reportedUserId, result.Name, result.ReportCount));
        if (result.HiddenNow)
        {
            logger.LogInformation("Name auto-hidden for user {UserId} after {ReportCount} reports (case {CaseId})",
                reportedUserId, result.ReportCount, result.CaseId);
            alerts.Raise(ModerationAlert.ForCase(ModerationAlertKind.AutoHidden, result.CaseId, reportedUserId, result.Name, result.ReportCount));
        }
        return result.Outcome;
    }

    private async Task<ReportResult> RecordReportAsync(Guid reporterId, Guid reportedUserId, NameReportReason reason)
    {
        db.ChangeTracker.Clear();
        await using var tx = await db.Database.BeginTransactionAsync();

        // Serialises every report against this player: two concurrent "third" reports can then
        // neither both see a count of 2 (missed hide) nor both hide (double alert).
        await ModerationLocks.LockUserAsync(db, reportedUserId);

        var target = await db.Users.AsNoTracking()
            .Where(u => u.Id == reportedUserId)
            .Select(u => new { u.DisplayName, u.NameHiddenAt })
            .SingleOrDefaultAsync();
        if (target is null) return new ReportResult(NameReportOutcome.NotFound);
        if (target.NameHiddenAt != null) return new ReportResult(NameReportOutcome.Ignored);

        var now = DateTime.UtcNow;
        // Re-checked under the lock: the early check above is only there to keep moderators hidden.
        if (await CountReportsTodayAsync(reporterId, now) >= GameConstants.MaxNameReportsPerReporterPerDay)
            return new ReportResult(NameReportOutcome.DailyLimitReached);

        var inserted = await db.Database.ExecuteSqlInterpolatedAsync($@"
            INSERT INTO ""NameReports"" (""Id"", ""ReporterId"", ""ReportedUserId"", ""NameSnapshot"", ""Reason"", ""CreatedAt"")
            VALUES ({Guid.NewGuid()}, {reporterId}, {reportedUserId}, {target.DisplayName}, {(short)reason}, {now})
            ON CONFLICT (""ReporterId"", ""ReportedUserId"", ""NameSnapshot"") DO NOTHING");
        if (inserted == 0) return new ReportResult(NameReportOutcome.Ignored);

        var caseOpenedNow = await OpenCaseAsync(reportedUserId, target.DisplayName, now) == 1;
        var reviewCase = await db.NameModerationCases.AsNoTracking()
            .SingleAsync(c => c.UserId == reportedUserId && c.NameSnapshot == target.DisplayName);

        // Only reports in the current window count, so a name a moderator restored is not
        // re-hidden by the reports that were already judged.
        var reportCount = await db.NameReports.CountAsync(r =>
            r.ReportedUserId == reportedUserId
            && r.NameSnapshot == target.DisplayName
            && r.CreatedAt >= reviewCase.OpenedAt);

        var hiddenNow = false;
        // AutoHidden too: if the name is showing again despite an open hide decision, hide it again.
        if (reportCount >= GameConstants.NameReportHideThreshold
            && reviewCase.Status is ModerationCaseStatus.Open or ModerationCaseStatus.AutoHidden)
        {
            hiddenNow = await NameHiding.HideAsync(db, reportedUserId, target.DisplayName, now);
            if (hiddenNow)
            {
                await db.NameModerationCases.Where(c => c.Id == reviewCase.Id).ExecuteUpdateAsync(s => s
                    .SetProperty(c => c.Status, ModerationCaseStatus.AutoHidden)
                    .SetProperty(c => c.HiddenAt, now));
            }
        }

        await tx.CommitAsync();
        return new ReportResult(NameReportOutcome.Accepted, reviewCase.Id, target.DisplayName, reportCount, caseOpenedNow, hiddenNow);
    }

    private Task<int> CountReportsTodayAsync(Guid reporterId, DateTime now) =>
        db.NameReports.CountAsync(r => r.ReporterId == reporterId && r.CreatedAt >= now.Date);

    /// <summary>
    /// Creates the review case for this name, or reopens one a moderator restored. Returns 1 when
    /// this call opened the window — the once-only "first report" signal — and 0 when a case was
    /// already open, hidden or confirmed.
    /// </summary>
    private Task<int> OpenCaseAsync(Guid userId, string name, DateTime now) =>
        db.Database.ExecuteSqlInterpolatedAsync($@"
            INSERT INTO ""NameModerationCases"" (""Id"", ""UserId"", ""NameSnapshot"", ""Source"", ""Status"", ""OpenedAt"")
            VALUES ({Guid.NewGuid()}, {userId}, {name}, {(short)ModerationCaseSource.Reports}, {(short)ModerationCaseStatus.Open}, {now})
            ON CONFLICT (""UserId"", ""NameSnapshot"") DO UPDATE SET
                ""Status"" = {(short)ModerationCaseStatus.Open},
                ""Source"" = {(short)ModerationCaseSource.Reports},
                ""OpenedAt"" = {now},
                ""HiddenAt"" = NULL,
                ""ResolvedAt"" = NULL,
                ""ResolvedByUid"" = NULL
            WHERE ""NameModerationCases"".""Status"" = {(short)ModerationCaseStatus.Restored}");
}
