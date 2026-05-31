using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Services;

namespace MyLoop.Api.Controllers;

/// <summary>
/// Handles leaderboard queries and refresh.
/// </summary>
[ApiController]
[Route("api/leaderboard")]
[Authorize]
public class LeaderboardController : ControllerBase
{
    private readonly ILeaderboardService _leaderboardService;

    public LeaderboardController(ILeaderboardService leaderboardService)
    {
        _leaderboardService = leaderboardService;
    }

    /// <summary>
    /// Get today's leaderboard for a specific scope (city/country/world).
    /// Returns top 20 players + the requesting user's rank.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetLeaderboard(
        [FromQuery] double lat,
        [FromQuery] double lng,
        [FromQuery] Guid? userId,
        [FromQuery] string? scope)
    {
        var leaderboardScope = scope ?? "city";
        var result = await _leaderboardService.GetLeaderboard(lat, lng, userId, leaderboardScope);
        return Ok(result);
    }

    /// <summary>
    /// Refresh today's leaderboard from current territory data.
    /// In production this would be a scheduled job.
    /// </summary>
    [HttpPost("refresh")]
    public async Task<IActionResult> Refresh()
    {
        var playerCount = await _leaderboardService.RefreshLeaderboard();
        return Ok(new { Message = "Leaderboard refreshed", PlayerCount = playerCount });
    }
}
