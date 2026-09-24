using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;

namespace MyLoop.Api.Services.Moderation;

/// <summary>
/// The single hide/restore write, shared by reports, rescan and moderator confirm/restore so the
/// conditions stay identical everywhere. Both are conditional updates: they only change a row
/// that still holds the expected name, so a concurrent rename, hide or restore turns them into
/// a no-op instead of overwriting newer state.
/// </summary>
internal static class NameHiding
{
    /// <summary>Replaces <paramref name="expectedName"/> with the placeholder. True if this call hid it.</summary>
    public static async Task<bool> HideAsync(AppDbContext db, Guid userId, string expectedName, DateTime now)
    {
        var placeholder = NameModeration.PlaceholderFor(userId);
        var rows = await db.Users
            .Where(u => u.Id == userId && u.DisplayName == expectedName && u.NameHiddenAt == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(u => u.DisplayName, placeholder)
                .SetProperty(u => u.NameHiddenAt, now));
        return rows == 1;
    }

    /// <summary>
    /// Writes <paramref name="originalName"/> back, only while the placeholder from *this* hide is
    /// still showing: a player who renamed keeps their new name, and restoring an older case can't
    /// undo a newer hide of a different name (every hide writes the same instant to
    /// User.NameHiddenAt and the case's HiddenAt). True if this call restored it.
    /// </summary>
    public static async Task<bool> RestoreAsync(AppDbContext db, Guid userId, string originalName, DateTime hiddenAt)
    {
        var placeholder = NameModeration.PlaceholderFor(userId);
        var rows = await db.Users
            .Where(u => u.Id == userId && u.DisplayName == placeholder && u.NameHiddenAt == hiddenAt)
            .ExecuteUpdateAsync(s => s
                .SetProperty(u => u.DisplayName, originalName)
                .SetProperty(u => u.NameHiddenAt, (DateTime?)null));
        return rows == 1;
    }
}
