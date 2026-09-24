using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Constants;
using MyLoop.Api.Entities;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Models;

namespace MyLoop.Api.Controllers;

/// <summary>
/// Moderator review of display names (DR-002b, #190). Every action requires the Moderator policy
/// (Firebase UID on Moderation:ModeratorUids); anyone else gets 403.
/// </summary>
[ApiController]
[Route("api/moderation")]
[Authorize(Policy = AuthorizationPolicies.Moderator)]
public class ModerationController(IModerationService moderation, ICurrentUser currentUser) : ControllerBase
{
    private static readonly ModerationCaseStatus[] PendingStatuses = [ModerationCaseStatus.Open, ModerationCaseStatus.AutoHidden];

    /// <summary>The review queue. <paramref name="status"/>: open, autoHidden, confirmed or restored; default open + autoHidden.</summary>
    [HttpGet("cases")]
    public async Task<IActionResult> ListCases([FromQuery] string? status)
    {
        if (status is null) return Ok(await moderation.ListCasesAsync(PendingStatuses));
        if (!Enum.TryParse<ModerationCaseStatus>(status, ignoreCase: true, out var parsed) || !Enum.IsDefined(parsed))
            return BadRequest($"Unknown status '{status}'");
        return Ok(await moderation.ListCasesAsync([parsed]));
    }

    [HttpPost("cases/{caseId:guid}/confirm")]
    public async Task<IActionResult> Confirm([FromRoute] Guid caseId) =>
        ToResult(await moderation.ConfirmAsync(caseId, currentUser.FirebaseUid!));

    [HttpPost("cases/{caseId:guid}/restore")]
    public async Task<IActionResult> Restore([FromRoute] Guid caseId) =>
        ToResult(await moderation.RestoreAsync(caseId, currentUser.FirebaseUid!));

    [HttpPost("users/{userId:guid}/unlock-name")]
    public async Task<IActionResult> UnlockName([FromRoute] Guid userId) =>
        await moderation.UnlockNameAsync(userId, currentUser.FirebaseUid!) ? NoContent() : NotFound();

    /// <summary>Re-checks every visible name against the current blocklist; run after updating it.</summary>
    [HttpPost("rescan")]
    public async Task<ActionResult<RescanResponse>> Rescan(CancellationToken cancellationToken) =>
        Ok(await moderation.RescanAsync(cancellationToken));

    private IActionResult ToResult(ModerationDecisionOutcome outcome) => outcome switch
    {
        ModerationDecisionOutcome.Done => NoContent(),
        ModerationDecisionOutcome.NotFound => NotFound(),
        ModerationDecisionOutcome.InvalidState => Conflict(),
        _ => throw new InvalidOperationException($"Unhandled decision outcome {outcome}"),
    };
}
