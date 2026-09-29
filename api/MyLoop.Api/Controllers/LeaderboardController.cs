using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Services;

namespace MyLoop.Api.Controllers;

/// <summary>
/// Handles leaderboard queries. Refresh runs on a background timer
/// (<see cref="LeaderboardRefreshWorker"/>), not on client request — see #109.
/// </summary>
[ApiController]
[Route("api/leaderboard")]
[Authorize]
public class LeaderboardController : ControllerBase
{
    private readonly ILeaderboardService _leaderboardService;
    private readonly ICurrentUser _currentUser;

    public LeaderboardController(ILeaderboardService leaderboardService, ICurrentUser currentUser)
    {
        _leaderboardService = leaderboardService;
        _currentUser = currentUser;
    }

    /// <summary>
    /// Get today's leaderboard for a specific scope (city/country/world). Single-player 0.1:
    /// only the caller's own entry and rank, never other players (bug B1). The old
    /// <c>userId</c> query parameter is ignored so a caller can't ask for someone else's rank.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetLeaderboard(
        [FromQuery] double lat,
        [FromQuery] double lng,
        [FromQuery] string? scope)
    {
        var callerId = await _currentUser.TryGetUserIdAsync();
        if (callerId is null) return Unauthorized();

        var leaderboardScope = scope ?? "city";
        var result = await _leaderboardService.GetLeaderboard(lat, lng, callerId, leaderboardScope);
        return Ok(result);
    }
}
