namespace MyLoop.Api.Entities;

/// <summary>How a name entered moderation.</summary>
public enum ModerationCaseSource : short
{
    Reports = 0,
    Rescan = 1,
}

/// <summary>Lifecycle of a moderated name.</summary>
public enum ModerationCaseStatus : short
{
    /// <summary>Reported, below the hide threshold, awaiting review.</summary>
    Open = 0,
    /// <summary>Hidden automatically (report threshold or rescan); awaiting review.</summary>
    AutoHidden = 1,
    /// <summary>A moderator agreed the name breaks the rules (counts as a strike).</summary>
    Confirmed = 2,
    /// <summary>A moderator restored or dismissed it; new reports reopen the case.</summary>
    Restored = 3,
}

/// <summary>
/// Review record for one (user, name) pair (DR-002b, #190). Unique on (UserId, NameSnapshot): the
/// insert of this row is the "first report" claim, so exactly one request sends the first-report
/// alert. <see cref="NameSnapshot"/> is what a restore writes back.
/// </summary>
public class NameModerationCase
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public required string NameSnapshot { get; set; }
    public ModerationCaseSource Source { get; set; }
    public ModerationCaseStatus Status { get; set; }
    /// <summary>Start of the current review window; only reports at or after it count toward the hide threshold.</summary>
    public DateTime OpenedAt { get; set; }
    public DateTime? HiddenAt { get; set; }
    public DateTime? ResolvedAt { get; set; }
    /// <summary>Firebase UID of the moderator who confirmed/restored — audit trail.</summary>
    public string? ResolvedByUid { get; set; }
}
