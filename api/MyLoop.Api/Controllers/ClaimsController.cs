using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Constants;
using MyLoop.Api.Models;
using MyLoop.Api.Services;

namespace MyLoop.Api.Controllers;

/// <summary>
/// Handles territory claim submission.
/// </summary>
[ApiController]
[Route("api/claims")]
[Authorize]
public class ClaimsController : ControllerBase
{
    private readonly ITerritoryService _territoryService;
    private readonly IHexGridService _hexGridService;

    public ClaimsController(ITerritoryService territoryService, IHexGridService hexGridService)
    {
        _territoryService = territoryService;
        _hexGridService = hexGridService;
    }

    /// <summary>
    /// Submit a territory claim. The user walked a path — we compute
    /// which hexes they captured and assign ownership.
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> SubmitClaim([FromBody] ClaimRequest request)
    {
        var result = await _territoryService.ProcessClaim(request.UserId, request.Path);

        if (!result.Success)
        {
            return BadRequest(result.Error);
        }

        return Created($"/api/claims/{result.Data!.Id}", result.Data);
    }

    /// <summary>
    /// Preview which hexes a path would capture — no DB writes.
    /// Called by the client during a walk when a loop is detected,
    /// so the user can see hex fills appearing in real-time.
    /// </summary>
    [HttpPost("preview")]
    public IActionResult PreviewClaim([FromBody] PreviewRequest request)
    {
        if (request.Path.Length < GameConstants.MinPointsForPolygon)
            return Ok(new { boundaries = Array.Empty<double[][]>() });

        // Cap path length to prevent CPU abuse (same as claim validation spirit)
        if (request.Path.Length > GameConstants.MaxPreviewPathLength)
            return BadRequest("Path too long for preview");

        try
        {
            var cells = _hexGridService.ComputeCapturedCells(request.Path);
            var boundaries = cells.Select(c => c.Boundary).ToArray();
            return Ok(new { boundaries });
        }
        catch (Exception)
        {
            // Preview is best-effort — return empty on any computation failure
            return Ok(new { boundaries = Array.Empty<double[][]>() });
        }
    }
}
