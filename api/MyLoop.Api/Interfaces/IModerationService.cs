using MyLoop.Api.Entities;
using MyLoop.Api.Models;

namespace MyLoop.Api.Interfaces;

/// <summary>Outcome of a moderator decision on a case.</summary>
public enum ModerationDecisionOutcome
{
    Done,
    NotFound,
    /// <summary>The case is in a state this decision does not apply to (e.g. restoring a confirmed case).</summary>
    InvalidState,
}

/// <summary>Moderator review of names (DR-002b, #190). Callers are authorized by the Moderator policy.</summary>
public interface IModerationService
{
    /// <summary>Cases in the given statuses, oldest first.</summary>
    Task<IReadOnlyList<ModerationCaseResponse>> ListCasesAsync(IReadOnlyCollection<ModerationCaseStatus> statuses);

    /// <summary>Confirms the name breaks the rules: hides it if still showing and adds a strike.</summary>
    Task<ModerationDecisionOutcome> ConfirmAsync(Guid caseId, string moderatorUid);

    /// <summary>Restores a hidden name (if the placeholder still shows) or dismisses an open case.</summary>
    Task<ModerationDecisionOutcome> RestoreAsync(Guid caseId, string moderatorUid);

    /// <summary>Lets a strike-locked player rename again. False when the user does not exist.</summary>
    Task<bool> UnlockNameAsync(Guid userId);

    /// <summary>Re-checks every visible name against the current blocklist and hides matches.</summary>
    Task<RescanResponse> RescanAsync(CancellationToken cancellationToken);

    /// <summary>True when a moderator already confirmed this exact name for this player.</summary>
    Task<bool> IsConfirmedRemovedNameAsync(Guid userId, string normalizedName);
}
