namespace MyLoop.Api.Models;

/// <summary>
/// An achievement unlocked as a side-effect of a claim, surfaced to the client so it
/// can show an unlock toast. Returned by the batch-step claim path.
/// </summary>
public class AchievementUnlockedDto
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Icon { get; set; } = "";
    public int XpAwarded { get; set; }
}
