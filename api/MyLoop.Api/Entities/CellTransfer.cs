namespace MyLoop.Api.Entities;

/// <summary>
/// Records a single ownership transfer event for a territory hex cell.
/// Created every time a cell changes hands (or is claimed for the first time).
/// Powers the "revenge recapture" feature — players can see which hexes were stolen
/// from them and by whom, enabling a Clash-of-Clans-style raid-and-revenge loop.
/// </summary>
public class CellTransfer
{
    /// <summary>Unique identifier for this transfer event.</summary>
    public Guid Id { get; set; }

    /// <summary>The H3 cell that changed ownership.</summary>
    public long CellId { get; set; }

    /// <summary>
    /// The user who previously owned this cell (null if the cell was unclaimed before).
    /// This is the "victim" in a steal scenario.
    /// </summary>
    public Guid? FromUserId { get; set; }

    /// <summary>The user who captured this cell. This is the "attacker" in a steal scenario.</summary>
    public Guid ToUserId { get; set; }

    /// <summary>The claim (walk submission) that triggered this ownership change.</summary>
    public Guid ClaimId { get; set; }

    /// <summary>Timestamp when the transfer occurred.</summary>
    public DateTime TransferredAt { get; set; }
}
