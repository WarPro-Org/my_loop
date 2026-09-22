using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Models;

namespace MyLoop.Api.Controllers;

/// <summary>Players reporting another player's display name (DR-002b, #190).</summary>
[ApiController]
[Route("api/users")]
[Authorize]
public class NameReportsController(INameReportService reports, ICurrentUser currentUser) : ControllerBase
{
    private const string SelfReportMessage = "You can't report your own name";
    private const string DailyLimitMessage = "You've reached today's report limit";

    /// <summary>
    /// Report the display name of player <paramref name="id"/>. The reporter is always the
    /// authenticated caller. Repeat reports, already-hidden names and some targets are accepted
    /// silently (204) so the response reveals nothing about moderation state.
    /// </summary>
    [HttpPost("{id:guid}/name-report")]
    public async Task<IActionResult> Report([FromRoute] Guid id, [FromBody] NameReportRequest request)
    {
        var reporterId = await currentUser.TryGetUserIdAsync();
        if (reporterId is null) return Unauthorized();

        var outcome = await reports.ReportAsync(reporterId.Value, id, request.Reason!.Value);
        return outcome switch
        {
            NameReportOutcome.Accepted or NameReportOutcome.Ignored => NoContent(),
            NameReportOutcome.SelfReport => BadRequest(SelfReportMessage),
            NameReportOutcome.NotFound => NotFound(),
            NameReportOutcome.DailyLimitReached => StatusCode(StatusCodes.Status429TooManyRequests, DailyLimitMessage),
            _ => throw new InvalidOperationException($"Unhandled report outcome {outcome}"),
        };
    }
}
