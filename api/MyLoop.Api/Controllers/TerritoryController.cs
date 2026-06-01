using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Services;

namespace MyLoop.Api.Controllers;

/// <summary>
/// Handles territory queries — viewport cells, stats, stolen cells, history.
/// </summary>
[ApiController]
[Route("api/territories")]
[Authorize]
public class TerritoryController : ControllerBase
{
    private readonly ITerritoryService _territoryService;

    public TerritoryController(ITerritoryService territoryService)
    {
        _territoryService = territoryService;
    }

    /// <summary>
    /// Get all territory cells within a map viewport bounding box.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetTerritoriesInViewport(
        [FromQuery] double minLat,
        [FromQuery] double minLng,
        [FromQuery] double maxLat,
        [FromQuery] double maxLng)
    {
        var territories = await _territoryService.GetTerritoriesInViewport(minLat, minLng, maxLat, maxLng);
        return Ok(territories);
    }

    /// <summary>
    /// Get a user's total territory stats (cell count + area).
    /// </summary>
    [HttpGet("stats/{userId:guid}")]
    public async Task<IActionResult> GetStats([FromRoute] Guid userId)
    {
        var stats = await _territoryService.GetUserStats(userId);
        return Ok(stats);
    }

    /// <summary>
    /// Get hexes that were stolen from this user within N days.
    /// Used for the revenge recapture feature.
    /// </summary>
    [HttpGet("stolen/{userId:guid}")]
    public async Task<IActionResult> GetStolenCells(
        [FromRoute] Guid userId,
        [FromQuery] int days = 7)
    {
        var result = await _territoryService.GetStolenCells(userId, days);
        return Ok(result);
    }

    /// <summary>
    /// Get the full ownership history of a specific hex cell.
    /// </summary>
    [HttpGet("history/{cellId:long}")]
    public async Task<IActionResult> GetCellHistory([FromRoute] long cellId)
    {
        var result = await _territoryService.GetCellHistory(cellId);
        return Ok(result);
    }

    /// <summary>
    /// Get ALL territory cells owned by a specific user (no viewport limit).
    /// Used by the mobile map to always show the user's hexes regardless of location.
    /// </summary>
    [HttpGet("user/{userId:guid}")]
    public async Task<IActionResult> GetUserTerritories([FromRoute] Guid userId)
    {
        var cells = await _territoryService.GetUserTerritories(userId);
        return Ok(cells);
    }

    /// <summary>
    /// Get a user's claim history — one entry per walk submission.
    /// Used for the "Hex History" section on the home page.
    /// </summary>
    [HttpGet("claims/{userId:guid}")]
    public async Task<IActionResult> GetClaimHistory([FromRoute] Guid userId)
    {
        var history = await _territoryService.GetClaimHistory(userId);
        return Ok(history);
    }

    /// <summary>
    /// Get exploration stats for neighborhoods near a GPS point.
    /// Returns explored % for each nearby neighborhood (H3 res 8).
    /// </summary>
    [HttpGet("exploration/{userId:guid}")]
    public async Task<IActionResult> GetExplorationStats(
        [FromRoute] Guid userId,
        [FromQuery] double lat,
        [FromQuery] double lng)
    {
        var stats = await _territoryService.GetExplorationStats(userId, lat, lng);
        return Ok(stats);
    }
}
