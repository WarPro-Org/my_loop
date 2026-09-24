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
        // show again while its case can no longer re-hide it.
        var removed = await db.NameModerationCases.AnyAsync(c =>
            c.UserId == userId
            && c.NameSnapshot == normalizedName
            && (c.Status == ModerationCaseStatus.Confirmed || c.Status == ModerationCaseStatus.AutoHidden));
        return removed ? RenameCheck.RemovedName : RenameCheck.Allowed;
    }
}
