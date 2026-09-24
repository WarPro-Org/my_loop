namespace MyLoop.Api.Entities;

/// <summary>
/// <see cref="BlockerId"/> no longer sees <see cref="BlockedId"/>'s identity (DR-002b, #190):
/// their name is masked on the blocker's leaderboard, map and notifications. Blocking never
/// affects gameplay — territory stays contestable both ways.
/// </summary>
public class UserBlock
{
    public Guid BlockerId { get; set; }
    public Guid BlockedId { get; set; }
    public DateTime CreatedAt { get; set; }
}
