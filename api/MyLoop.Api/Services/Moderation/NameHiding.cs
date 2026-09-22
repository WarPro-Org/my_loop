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
    /// Writes <paramref name="originalName"/> back, only while the placeholder is still showing —
    /// a player who renamed after the hide keeps their new name. True if this call restored it.
    /// </summary>
    public static async Task<bool> RestoreAsync(AppDbContext db, Guid userId, string originalName)
    {
        var placeholder = NameModeration.PlaceholderFor(userId);
        var rows = await db.Users
            .Where(u => u.Id == userId && u.DisplayName == placeholder && u.NameHiddenAt != null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(u => u.DisplayName, originalName)
                .SetProperty(u => u.NameHiddenAt, (DateTime?)null));
        return rows == 1;
    }
}
