using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Constants;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Models;
using MyLoop.Api.Services.Moderation.Alerts;

namespace MyLoop.Api.Services.Moderation;

/// <summary>Moderator review of reported and rescanned names (DR-002b, #190).</summary>
public sealed class ModerationService(
    AppDbContext db,
    IModerationAlerts alerts,
    ILogger<ModerationService> logger) : IModerationService
{
    private const int MaxCasesListed = 200;

    public async Task<IReadOnlyList<ModerationCaseResponse>> ListCasesAsync(IReadOnlyCollection<ModerationCaseStatus> statuses)
    {
        // A plain array parameter is what EF translates to "= ANY(@p)"; don't hand it an arbitrary collection type.
        var wanted = statuses.ToArray();
        var rows = await (
            from c in db.NameModerationCases.AsNoTracking()
            join u in db.Users.AsNoTracking() on c.UserId equals u.Id
            where wanted.Contains(c.Status)
            orderby c.OpenedAt
            select new
            {
                Case = c,
                u.DisplayName,
                u.ConfirmedNameStrikes,
                u.NameLockedAt,
                Reports = db.NameReports
                    .Where(r => r.ReportedUserId == c.UserId && r.NameSnapshot == c.NameSnapshot && r.CreatedAt >= c.OpenedAt)
                    .Select(r => r.Reason)
                    .ToList(),
            })
            .Take(MaxCasesListed)
            .ToListAsync();

        return rows.Select(r => new ModerationCaseResponse
        {
            Id = r.Case.Id,
            UserId = r.Case.UserId,
            NameSnapshot = r.Case.NameSnapshot,
            CurrentDisplayName = r.DisplayName,
            Source = JsonNamingPolicy.CamelCase.ConvertName(r.Case.Source.ToString()),
            Status = JsonNamingPolicy.CamelCase.ConvertName(r.Case.Status.ToString()),
            ReportCount = r.Reports.Count,
            Reasons = r.Reports.Distinct().Select(x => JsonNamingPolicy.CamelCase.ConvertName(x.ToString())).ToList(),
            ConfirmedStrikes = r.ConfirmedNameStrikes,
            NameLocked = r.NameLockedAt != null,
            OpenedAt = r.Case.OpenedAt,
            HiddenAt = r.Case.HiddenAt,
        }).ToList();
    }

    public Task<ModerationDecisionOutcome> ConfirmAsync(Guid caseId, string moderatorUid) =>
        db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync();
            var reviewCase = await LockCaseAsync(caseId);
            if (reviewCase is null) return ModerationDecisionOutcome.NotFound;
            if (reviewCase.Status == ModerationCaseStatus.Confirmed) return ModerationDecisionOutcome.Done;
            if (reviewCase.Status == ModerationCaseStatus.Restored) return ModerationDecisionOutcome.InvalidState;

            var now = DateTime.UtcNow;
            // An open case is confirmed before it reached the threshold: hide it now (a no-op if
            // the player already renamed).
            var hiddenAt = reviewCase.HiddenAt;
            if (reviewCase.Status == ModerationCaseStatus.Open
                && await NameHiding.HideAsync(db, reviewCase.UserId, reviewCase.NameSnapshot, now))
                hiddenAt = now;

            // Increment and lock in SQL so the strike count cannot be lost to a concurrent write.
            await db.Users.Where(u => u.Id == reviewCase.UserId)
                .ExecuteUpdateAsync(s => s.SetProperty(u => u.ConfirmedNameStrikes, u => u.ConfirmedNameStrikes + 1));
            await db.Users
                .Where(u => u.Id == reviewCase.UserId
                    && u.ConfirmedNameStrikes >= GameConstants.NameStrikesToLock
                    && u.NameLockedAt == null)
                .ExecuteUpdateAsync(s => s.SetProperty(u => u.NameLockedAt, now));

            await ResolveAsync(caseId, ModerationCaseStatus.Confirmed, moderatorUid, now, hiddenAt);
            await tx.CommitAsync();
            logger.LogInformation("Moderator {ModeratorUid} confirmed case {CaseId} for user {UserId}",
                moderatorUid, caseId, reviewCase.UserId);
            return ModerationDecisionOutcome.Done;
        });

    public Task<ModerationDecisionOutcome> RestoreAsync(Guid caseId, string moderatorUid) =>
        db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync();
            var reviewCase = await LockCaseAsync(caseId);
            if (reviewCase is null) return ModerationDecisionOutcome.NotFound;
            if (reviewCase.Status == ModerationCaseStatus.Restored) return ModerationDecisionOutcome.Done;
            // A confirmed decision carries a strike; reversing it is a separate, deliberate action.
            if (reviewCase.Status == ModerationCaseStatus.Confirmed) return ModerationDecisionOutcome.InvalidState;

            if (reviewCase.Status == ModerationCaseStatus.AutoHidden)
                await NameHiding.RestoreAsync(db, reviewCase.UserId, reviewCase.NameSnapshot);

            await ResolveAsync(caseId, ModerationCaseStatus.Restored, moderatorUid, DateTime.UtcNow, reviewCase.HiddenAt);
            await tx.CommitAsync();
            logger.LogInformation("Moderator {ModeratorUid} restored case {CaseId} for user {UserId}",
                moderatorUid, caseId, reviewCase.UserId);
            return ModerationDecisionOutcome.Done;
        });

    public async Task<bool> UnlockNameAsync(Guid userId)
    {
        var exists = await db.Users.AnyAsync(u => u.Id == userId);
        if (!exists) return false;
        await db.Users.Where(u => u.Id == userId)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.NameLockedAt, (DateTime?)null));
        return true;
    }

    public async Task<RescanResponse> RescanAsync(CancellationToken cancellationToken)
    {
        var scanned = 0;
        var hidden = new List<string>();

        while (true)
        {
            // Paged so memory stays flat. Hiding changes rows but never removes them; a player who
            // registers mid-scan can shift a page and be skipped, which is harmless because their
            // name already passed the blocklist at registration.
            var page = await db.Users.AsNoTracking()
                .OrderBy(u => u.Id)
                .Skip(scanned)
                .Take(GameConstants.NameRescanPageSize)
                .Select(u => new { u.Id, u.DisplayName, u.NameHiddenAt })
                .ToListAsync(cancellationToken);
            if (page.Count == 0) break;
            scanned += page.Count;

            foreach (var user in page)
            {
                if (user.NameHiddenAt != null || !IsBlockedName(user.Id, user.DisplayName)) continue;
                var caseId = await HideForRescanAsync(user.Id, user.DisplayName);
                if (caseId is { } id) hidden.Add($"Case {id} — user {user.Id} — \"{user.DisplayName}\"");
            }
        }

        if (hidden.Count > 0)
            alerts.Raise(new ModerationAlert(ModerationAlertKind.RescanDigest, null, null, null, 0, hidden));
        logger.LogInformation("Name rescan checked {Scanned} users and hid {Hidden}", scanned, hidden.Count);
        return new RescanResponse(scanned, hidden.Count);
    }

    public async Task<RenameCheck> CheckRenameAsync(Guid userId, string requestedName)
    {
        var locked = await db.Users.AnyAsync(u => u.Id == userId && u.NameLockedAt != null);
        if (locked) return RenameCheck.Locked;

        var normalized = ValidationService.NormalizeDisplayName(requestedName);
        var removed = await db.NameModerationCases.AnyAsync(c =>
            c.UserId == userId && c.NameSnapshot == normalized && c.Status == ModerationCaseStatus.Confirmed);
        return removed ? RenameCheck.RemovedName : RenameCheck.Allowed;
    }

    /// <summary>Stored names predate #189's normalisation, so normalise before matching.</summary>
    private bool IsBlockedName(Guid userId, string storedName)
    {
        try
        {
            return NameModeration.IsBlocked(ValidationService.NormalizeDisplayName(storedName));
        }
        catch (ArgumentException ex)
        {
            // Ill-formed UTF-16 cannot be normalised or matched; leave it to player reports.
            logger.LogWarning(ex, "Rescan skipped user {UserId}: stored name cannot be normalised", userId);
            return false;
        }
    }

    /// <summary>
    /// Hides one rescan match in its own short transaction. Skips a name a moderator already
    /// restored — that was a human decision that the name is fine. Returns the case id if hidden.
    /// </summary>
    private Task<Guid?> HideForRescanAsync(Guid userId, string name) =>
        db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync();
            var existing = await db.NameModerationCases.AsNoTracking()
                .SingleOrDefaultAsync(c => c.UserId == userId && c.NameSnapshot == name);
            if (existing?.Status is ModerationCaseStatus.Restored or ModerationCaseStatus.Confirmed)
                return (Guid?)null;

            var now = DateTime.UtcNow;
            if (!await NameHiding.HideAsync(db, userId, name, now))
            {
                // Already hidden for this name: either a report beat us to it, or this is an
                // execution-strategy retry of a block that already committed. Either way the name
                // is hidden, so it belongs in the digest.
                return existing?.Status == ModerationCaseStatus.AutoHidden ? existing.Id : (Guid?)null;
            }

            Guid caseId;
            if (existing is null)
            {
                caseId = Guid.NewGuid();
                db.NameModerationCases.Add(new NameModerationCase
                {
                    Id = caseId,
                    UserId = userId,
                    NameSnapshot = name,
                    Source = ModerationCaseSource.Rescan,
                    Status = ModerationCaseStatus.AutoHidden,
                    OpenedAt = now,
                    HiddenAt = now,
                });
                await db.SaveChangesAsync();
            }
            else
            {
                caseId = existing.Id;
                await db.NameModerationCases.Where(c => c.Id == caseId).ExecuteUpdateAsync(s => s
                    .SetProperty(c => c.Status, ModerationCaseStatus.AutoHidden)
                    .SetProperty(c => c.HiddenAt, now));
            }
            await tx.CommitAsync();
            return caseId;
        });

    /// <summary>Row-locks the case so two moderators deciding at once are serialised.</summary>
    private async Task<NameModerationCase?> LockCaseAsync(Guid caseId)
    {
        await db.Database.ExecuteSqlInterpolatedAsync(
            $@"SELECT 1 FROM ""NameModerationCases"" WHERE ""Id"" = {caseId} FOR UPDATE");
        return await db.NameModerationCases.AsNoTracking().SingleOrDefaultAsync(c => c.Id == caseId);
    }

    private Task ResolveAsync(Guid caseId, ModerationCaseStatus status, string moderatorUid, DateTime now, DateTime? hiddenAt) =>
        db.NameModerationCases.Where(c => c.Id == caseId).ExecuteUpdateAsync(s => s
            .SetProperty(c => c.Status, status)
            .SetProperty(c => c.ResolvedAt, now)
            .SetProperty(c => c.ResolvedByUid, moderatorUid)
            .SetProperty(c => c.HiddenAt, hiddenAt));
}
