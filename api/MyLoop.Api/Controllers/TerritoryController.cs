using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Services;

namespace MyLoop.Api.Controllers;

/// <summary>
/// Handles territory queries — viewport cells, stats, stolen cells, history.
/// </summary>
[ApiController]
[Route("api/territories")]
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
}
