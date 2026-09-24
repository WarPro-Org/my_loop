using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Interfaces;

namespace MyLoop.Api.Services.Moderation;

/// <summary>
/// The moderation checks on a rename (DR-002b §4.2). Only meaningful inside the rename's
/// transaction, after <see cref="ModerationLocks.LockUserAsync"/>: without the lock a strike or a
/// moderator decision can commit between this check and the save (#194 review).
/// </summary>
internal static class RenameGate
{
    /// <param name="normalizedName">The requested name after <see cref="ValidationService.NormalizeDisplayName"/>.</param>
    public static async Task<RenameCheck> CheckAsync(AppDbContext db, Guid userId, string normalizedName)
    {
        var locked = await db.Users.AnyAsync(u => u.Id == userId && u.NameLockedAt != null);
        if (locked) return RenameCheck.Locked;

        // AutoHidden as well as Confirmed: renaming straight back to a hidden name would put it on
        // show again while its case can no longer re-hide it. A player has only a handful of
        // cases, so they are compared in memory, where the comparison can ignore case and
        // normalise snapshots stored before #189 (#194 review).
        var removedNames = await db.NameModerationCases
            .Where(c => c.UserId == userId
                && (c.Status == ModerationCaseStatus.Confirmed || c.Status == ModerationCaseStatus.AutoHidden))
            .Select(c => c.NameSnapshot)
            .ToListAsync();
        var removed = removedNames.Any(snapshot =>
            string.Equals(NormalizeSnapshot(snapshot), normalizedName, StringComparison.OrdinalIgnoreCase));
        return removed ? RenameCheck.RemovedName : RenameCheck.Allowed;
    }

    /// <summary>
    /// Snapshots copy the stored name, which may predate #189's normalisation. Ill-formed UTF-16
    /// can't be normalised (and can't be requested either, since validation rejects it), so it is
    /// compared as stored.
    /// </summary>
    private static string NormalizeSnapshot(string snapshot)
    {
        try
        {
            return ValidationService.NormalizeDisplayName(snapshot);
        }
        catch (ArgumentException)
        {
            return snapshot;
        }
    }
}
