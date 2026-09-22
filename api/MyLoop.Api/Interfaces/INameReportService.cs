using MyLoop.Api.Entities;

namespace MyLoop.Api.Interfaces;

/// <summary>Result of a player reporting another player's display name.</summary>
public enum NameReportOutcome
{
    /// <summary>Recorded (and possibly hid the name).</summary>
    Accepted,
    /// <summary>Nothing recorded, deliberately indistinguishable from Accepted for the caller:
    /// a repeat report, a name that is already hidden, or a moderator target (never revealed).</summary>
    Ignored,
    SelfReport,
    NotFound,
    DailyLimitReached,
}

/// <summary>Player-facing name reporting (DR-002b, #190).</summary>
public interface INameReportService
{
    Task<NameReportOutcome> ReportAsync(Guid reporterId, Guid reportedUserId, NameReportReason reason);
}
