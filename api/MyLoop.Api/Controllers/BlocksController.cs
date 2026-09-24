using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Models;

namespace MyLoop.Api.Controllers;

/// <summary>
/// Blocking other players (DR-002b, #190; App Store Guideline 1.2). The blocker is always the
/// authenticated caller, so there is no "whose list" parameter to tamper with.
/// </summary>
[ApiController]
[Route("api/users")]
[Authorize]
public class BlocksController(IBlockService blocks, ICurrentUser currentUser) : ControllerBase
{
    private const string SelfBlockMessage = "You can't block yourself";
    private const string LimitMessage = "You've blocked the maximum number of players";

    [HttpGet("me/blocks")]
    public async Task<ActionResult<BlockListResponse>> List()
    {
        if (await currentUser.TryGetUserIdAsync() is not { } me) return Unauthorized();
        return Ok(new BlockListResponse(await blocks.ListBlockedAsync(me)));
    }

    [HttpPut("{id:guid}/block")]
    public async Task<IActionResult> Block([FromRoute] Guid id)
    {
        if (await currentUser.TryGetUserIdAsync() is not { } me) return Unauthorized();
        return await blocks.BlockAsync(me, id) switch
        {
            BlockOutcome.Done => NoContent(),
            BlockOutcome.SelfBlock => BadRequest(SelfBlockMessage),
            BlockOutcome.NotFound => NotFound(),
            BlockOutcome.LimitReached => Conflict(LimitMessage),
            var outcome => throw new InvalidOperationException($"Unhandled block outcome {outcome}"),
        };
    }

    [HttpDelete("{id:guid}/block")]
    public async Task<IActionResult> Unblock([FromRoute] Guid id)
    {
        if (await currentUser.TryGetUserIdAsync() is not { } me) return Unauthorized();
        await blocks.UnblockAsync(me, id);
        return NoContent();
    }
}
