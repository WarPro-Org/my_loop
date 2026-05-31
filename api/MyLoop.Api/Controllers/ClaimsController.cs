using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
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
    private readonly ILogger<ClaimsController> _logger;

    public ClaimsController(
        ITerritoryService territoryService,
        IHexGridService hexGridService,
        ILogger<ClaimsController> logger)
    {
        _territoryService = territoryService;
        _hexGridService = hexGridService;
        _logger = logger;
    }

    /// <summary>
    /// Submit a territory claim. The user walked a path — we compute
    /// which hexes they captured and assign ownership.
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> SubmitClaim([FromBody] ClaimRequest request)
    {
        if (!ValidatePathCoordinates(request.Path))
            return BadRequest("Invalid GPS coordinates in path");

        try
        {
            var result = await _territoryService.ProcessClaim(request.UserId, request.Path);

            if (!result.Success)
                return BadRequest(new { error = result.Error });

            return Created($"/api/claims/{result.Data!.Id}", result.Data);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Claim processing failed for user {UserId}", request.UserId);
            return StatusCode(500, new { error = "Claim processing failed. Please try again." });
        }
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

        if (request.Path.Length > GameConstants.MaxPreviewPathLength)
            return BadRequest("Path too long for preview");

        if (!ValidatePathCoordinates(request.Path))
            return Ok(new { boundaries = Array.Empty<double[][]>() });

        try
        {
            var cells = _hexGridService.ComputeCapturedCells(request.Path);
            var boundaries = cells.Select(c => c.Boundary).ToArray();
            return Ok(new { boundaries });
        }
        catch (Exception)
        {
            return Ok(new { boundaries = Array.Empty<double[][]>() });
        }
    }

    private static bool ValidatePathCoordinates(double[][] path)
    {
        foreach (var point in path)
        {
            if (point.Length < 2) return false;
            if (point[0] < -90 || point[0] > 90) return false;
            if (point[1] < -180 || point[1] > 180) return false;
            if (double.IsNaN(point[0]) || double.IsNaN(point[1])) return false;
            if (double.IsInfinity(point[0]) || double.IsInfinity(point[1])) return false;
        }
        return true;
    }
}
