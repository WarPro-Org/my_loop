using MyLoop.Api.Models;

namespace MyLoop.Api.Interfaces;

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
    /// Refreshes today's leaderboard from current territory data. The token lets
    /// <c>LeaderboardRefreshWorker</c> abandon a run (e.g. one waiting on another instance's
    /// advisory lock or a Neon cold-start retry) at host shutdown.
    /// </summary>
    Task<int> RefreshLeaderboard(CancellationToken ct = default);
}
