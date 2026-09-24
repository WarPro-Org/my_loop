using Microsoft.Extensions.Options;
using MyLoop.Api.Options;

namespace MyLoop.Api.Services.Moderation;

/// <summary>Answers "is this Firebase UID a moderator?" from <see cref="ModerationOptions"/>.</summary>
public interface IModeratorDirectory
{
    bool IsModerator(string? firebaseUid);
}

/// <summary>
/// Reads the allowlist through <see cref="IOptionsMonitor{TOptions}"/>, so removing a UID from
/// configuration revokes access without a restart (when the config source reloads).
/// </summary>
public sealed class ModeratorDirectory(IOptionsMonitor<ModerationOptions> options) : IModeratorDirectory
{
    public bool IsModerator(string? firebaseUid) =>
        !string.IsNullOrEmpty(firebaseUid)
        && options.CurrentValue.ModeratorUids.Contains(firebaseUid, StringComparer.Ordinal);
}
