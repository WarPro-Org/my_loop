namespace MyLoop.Api.Services.Moderation.Alerts;

/// <summary>What happened. One alert per state change — never one per report.</summary>
public enum ModerationAlertKind
{
    /// <summary>A name received its first report in a review window.</summary>
    FirstReport,
    /// <summary>A name reached the report threshold and was hidden.</summary>
    AutoHidden,
    /// <summary>A moderator rescan hid one or more existing names.</summary>
    RescanDigest,
}

/// <summary>
/// A moderation event for the team. Carries the reported name and ids — never the reporters'
/// identities. <see cref="Details"/> holds one line per hidden name for a digest.
/// </summary>
public sealed record ModerationAlert(
    ModerationAlertKind Kind,
    Guid? CaseId,
    Guid? UserId,
    string? NameSnapshot,
    int ReportCount,
    IReadOnlyList<string> Details)
{
    public static ModerationAlert ForCase(ModerationAlertKind kind, Guid caseId, Guid userId, string name, int reportCount) =>
        new(kind, caseId, userId, name, reportCount, []);
}
