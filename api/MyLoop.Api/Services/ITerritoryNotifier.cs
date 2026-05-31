namespace MyLoop.Api.Services;

/// <summary>
/// Broadcasts territory ownership changes to connected clients in real-time.
/// </summary>
public interface ITerritoryNotifier
{
    /// <summary>
    /// Notifies all clients subscribed to affected regions that hex ownership changed.
    /// </summary>
    /// <param name="changes">List of cells that changed ownership.</param>
    Task NotifyHexOwnershipChanged(IReadOnlyList<HexChangeEvent> changes);
}

/// <summary>
/// Represents a single hex ownership change for real-time broadcast.
/// </summary>
public record HexChangeEvent(
    string H3Index,
    double CenterLat,
    double CenterLng,
    Guid NewOwnerId,
    string NewOwnerColor,
    string NewOwnerDisplayName,
    Guid? PreviousOwnerId,
    long ParentCellId
);
