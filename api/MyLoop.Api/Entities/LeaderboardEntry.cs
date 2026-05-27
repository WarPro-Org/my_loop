namespace MyLoop.Api.Entities;

/// A snapshot of the leaderboard for one user on one day.
/// Computed by a daily batch job at midnight.
public class LeaderboardEntry
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public DateOnly Date { get; set; }
    public int CellCount { get; set; }
    public double AreaM2 { get; set; }
    public int Rank { get; set; }

    public User? User { get; set; }
}
