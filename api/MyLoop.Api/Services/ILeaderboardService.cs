using MyLoop.Api.Models;

namespace MyLoop.Api.Services;

/// <summary>
/// Leaderboard operations — querying and refreshing daily rankings.
/// </summary>
public interface ILeaderboardService
{
    /// <summary>
    /// Gets today's leaderboard filtered by scope (city/country/world).
    /// Includes the requesting user's rank if not in the top list.
    /// </summary>
    Task<LeaderboardResponse> GetLeaderboard(double lat, double lng, Guid? userId, string scope);

    /// <summary>
    /// Refreshes today's leaderboard from current territory data.
    /// </summary>
    Task<int> RefreshLeaderboard();
}
