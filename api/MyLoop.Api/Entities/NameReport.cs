namespace MyLoop.Api.Entities;

/// <summary>Why a player reported another player's display name (DR-002b, #190).</summary>
public enum NameReportReason : short
{
    Offensive = 0,
    Impersonation = 1,
    Other = 2,
}

/// <summary>
/// One player's report of another player's display name. <see cref="NameSnapshot"/> is the name
/// as it was when reported — names change, and a moderator must judge what was actually seen.
/// Unique per (reporter, reported user, name), so repeat reports of the same name never count twice.
/// </summary>
public class NameReport
{
    public Guid Id { get; set; }
    public Guid ReporterId { get; set; }
    public Guid ReportedUserId { get; set; }
    public required string NameSnapshot { get; set; }
    public NameReportReason Reason { get; set; }
    public DateTime CreatedAt { get; set; }
}
