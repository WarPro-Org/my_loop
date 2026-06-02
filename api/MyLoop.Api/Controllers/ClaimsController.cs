using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Hosting;
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
    private readonly IWebHostEnvironment _env;

    public ClaimsController(
        ITerritoryService territoryService,
        IHexGridService hexGridService,
        ILogger<ClaimsController> logger,
        IWebHostEnvironment env)
    {
        _territoryService = territoryService;
        _hexGridService = hexGridService;
        _logger = logger;
        _env = env;
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
    /// Real-time walk-through claim. Batches of GPS points are sent during a walk
    /// and hexes the user physically touches are claimed immediately.
    /// Returns claimed hex boundaries for instant rendering on the map.
    /// </summary>
    [HttpPost("trail")]
    public async Task<IActionResult> ClaimTrail([FromBody] TrailClaimRequest request)
    {
        if (!ValidatePathCoordinates(request.Points))
            return BadRequest("Invalid GPS coordinates");

        try
        {
            var result = await _territoryService.ProcessTrailClaim(request.UserId, request.Points);

            if (!result.Success)
                return BadRequest(new { error = result.Error });

            return Ok(result.Data);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Trail claim failed for user {UserId}", request.UserId);
            return StatusCode(500, new { error = "Trail claim processing failed." });
        }
    }

    /// <summary>
    /// Single-point real-time claim. Each GPS tick sends one point —
    /// if the user entered a new hex, it's claimed and the boundary returned
    /// for instant rendering. ~100ms round-trip at walking speed.
    /// </summary>
    [HttpPost("step")]
    public async Task<IActionResult> ClaimStep([FromBody] StepClaimRequest request)
    {
        if (request.Lat < -90 || request.Lat > 90 || request.Lng < -180 || request.Lng > 180)
            return BadRequest("Invalid coordinates");

        try
        {
            var result = await _territoryService.ProcessStepClaim(request.UserId, request.Lat, request.Lng);
            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Step claim failed for user {UserId}", request.UserId);
            return StatusCode(500, new { error = "Step claim failed." });
        }
    }

    /// <summary>
    /// Batch step claim. Receives N GPS points captured during a walk
    /// (drained from the client's persistent write-ahead log) and processes
    /// them atomically: single transaction, single SaveChanges, one consolidated
    /// SignalR push per slice. Resilient to flaky networks — clients retry the
    /// whole batch with exponential backoff until acknowledged.
    /// </summary>
    [HttpPost("batch-step")]
    public async Task<IActionResult> ClaimBatchStep([FromBody] BatchStepClaimRequest request)
    {
        if (request == null || request.Points == null || request.Points.Count == 0)
            return BadRequest("No points provided");

        if (request.Points.Count > 200)
            return BadRequest("Too many points in a single batch (max 200)");

        foreach (var p in request.Points)
        {
            if (p.Lat < -90 || p.Lat > 90 || p.Lng < -180 || p.Lng > 180)
                return BadRequest("Invalid coordinates in batch");
            if (double.IsNaN(p.Lat) || double.IsNaN(p.Lng) ||
                double.IsInfinity(p.Lat) || double.IsInfinity(p.Lng))
                return BadRequest("Invalid coordinates in batch");
        }

        try
        {
            var result = await _territoryService.ProcessBatchStepClaim(
                request.UserId, request.LocalDate, request.Points);
            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Batch step claim failed for user {UserId}", request.UserId);
            return StatusCode(500, new { error = "Batch step claim failed." });
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

    /// <summary>
    /// DEV-ONLY: Trigger a step claim without auth for E2E testing the SignalR push pipeline.
    /// Calls ProcessStepClaim directly and returns the push result.
    /// REMOVE BEFORE PRODUCTION.
    /// </summary>
    [AllowAnonymous]
    [HttpPost("dev/test-push")]
    public async Task<IActionResult> DevTestPush([FromBody] StepClaimRequest request)
    {
        if (!_env.IsDevelopment()) return NotFound();

        try
        {
            var result = await _territoryService.ProcessStepClaim(request.UserId, request.Lat, request.Lng);
            return Ok(new { success = true, result, message = "Push pipeline executed — check SignalR client" });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { success = false, error = ex.Message });
        }
    }

    /// <summary>
    /// DEV-ONLY: Batch step claim without auth for E2E testing the write pipeline.
    /// REMOVE BEFORE PRODUCTION.
    /// </summary>
    [AllowAnonymous]
    [HttpPost("dev/test-batch")]
    public async Task<IActionResult> DevTestBatch([FromBody] BatchStepClaimRequest request)
    {
        if (!_env.IsDevelopment()) return NotFound();

        try
        {
            var result = await _territoryService.ProcessBatchStepClaim(
                request.UserId, request.LocalDate, request.Points);
            return Ok(result);
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { success = false, error = ex.Message });
        }
    }
}
