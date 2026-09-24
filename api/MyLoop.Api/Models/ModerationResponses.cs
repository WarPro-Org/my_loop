using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;
using MyLoop.Api.Entities;

namespace MyLoop.Api.Models;

/// <summary>Body of <c>POST /api/users/{id}/name-reports</c>.</summary>
public sealed class NameReportRequest
{
    /// <summary>"offensive" | "impersonation" | "other".</summary>
    [Required]
    [JsonConverter(typeof(JsonStringEnumConverter<NameReportReason>))]
    public NameReportReason? Reason { get; init; }
}

/// <summary>One entry in the moderator review queue.</summary>
public sealed class ModerationCaseResponse
{
    public Guid Id { get; init; }
    public Guid UserId { get; init; }
    /// <summary>The name that was reported or matched — what the moderator is judging.</summary>
    public string NameSnapshot { get; init; } = "";
    /// <summary>What the player is called now (a placeholder while hidden, or a later rename).</summary>
    public string CurrentDisplayName { get; init; } = "";
    public string Source { get; init; } = "";
    public string Status { get; init; } = "";
    public int ReportCount { get; init; }
    public IReadOnlyList<string> Reasons { get; init; } = [];
    public int ConfirmedStrikes { get; init; }
    public bool NameLocked { get; init; }
    public DateTime OpenedAt { get; init; }
    public DateTime? HiddenAt { get; init; }
}

/// <summary>Result of <c>POST /api/moderation/rescan</c>.</summary>
public sealed record RescanResponse(int Scanned, int Hidden);

/// <summary>Machine-readable error for a rename refused because renaming is locked.</summary>
public sealed record NameLockedError(string Code, string Message);
