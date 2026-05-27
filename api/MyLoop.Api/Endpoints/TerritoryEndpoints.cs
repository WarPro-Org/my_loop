using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Services;

namespace MyLoop.Api.Endpoints;

/// <summary>
/// Territory and claims endpoints — the core game mechanic.
/// Handles submission of captured loops (claims), querying visible territory cells,
/// and retrieving per-user territory statistics.
/// </summary>
public static class TerritoryEndpoints
{
    /// <summary>
    /// Maps all territory-related HTTP endpoints under the <c>/api</c> route group.
    /// Includes claim submission, territory querying by bounding box, and user stats.
    /// </summary>
    /// <param name="app">The <see cref="WebApplication"/> to register routes on.</param>
    public static void MapTerritoryEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api");

        // POST /api/claims
        // Submit a claim. The user walked a path and the app sent it here.
        // We figure out which hexes the path crosses through + fills inside the loop.
        // If someone else owned those hexes, tough luck — they're yours now (last-writer-wins).
        group.MapPost("/claims", async (
            [FromBody] ClaimRequest request,
            AppDbContext db) =>
        {
            // Validation: path must have enough points (at least 10 GPS readings)
            if (request.Path.Length < 10)
                return Results.BadRequest("Path too short — need at least 10 GPS points");

            // Validation: path must be at least 200 meters long (anti-abuse measure
            // to prevent trivial claims from a stationary position)
            var totalDistance = 0.0;
            for (int i = 1; i < request.Path.Length; i++)
            {
                var p1 = request.Path[i - 1];
                var p2 = request.Path[i];
                // Sum the great-circle distance between consecutive GPS readings
                totalDistance += HaversineMeters(p1[0], p1[1], p2[0], p2[1]);
            }
            if (totalDistance < 200)
                return Results.BadRequest("Walk at least 200 meters before claiming");

            // Compute captured hexes: trail cells + enclosed area (if the path forms a closed loop)
            var cells = H3Service.ComputeCapturedCells(request.Path);
            if (cells.Count == 0)
                return Results.BadRequest("No hexes captured — try walking further");

            // Anti-abuse: cap individual claim size at 5 km² to prevent GPS spoofing exploits
            var area = H3Service.CalculateArea(cells.Count);
            if (area > 5_000_000)
                return Results.BadRequest("Claim too large — max 5km² per claim");

            // Create the claim record (the permanent log of this submission)
            var claim = new Claim
            {
                Id = Guid.NewGuid(),
                UserId = request.UserId,
                CellCount = cells.Count,
                AreaM2 = area,
            };
            claim.SetPolygon(request.Path);

            // Assign every hex inside the polygon to this user.
            // If a hex already has an owner, it gets overwritten (last-writer-wins territory model).
            foreach (var (cellId, boundary) in cells)
            {
                var existing = await db.TerritoryCells.FindAsync(cellId);
                if (existing is not null)
                {
                    // Steal: overwrite the previous owner of this hex
                    existing.OwnerId = request.UserId;
                    existing.ClaimId = claim.Id;
                    existing.ClaimedAt = DateTime.UtcNow;
                    existing.SetBoundary(boundary);
                }
                else
                {
                    // Fresh hex — nobody owned it yet, create a new record
                    var cell = new TerritoryCell
                    {
                        CellId = cellId,
                        OwnerId = request.UserId,
                        ClaimId = claim.Id,
                        ClaimedAt = DateTime.UtcNow,
                    };
                    cell.SetBoundary(boundary);
                    db.TerritoryCells.Add(cell);
                }
            }

            db.Claims.Add(claim);
            await db.SaveChangesAsync();

            return Results.Created($"/api/claims/{claim.Id}", new
            {
                claim.Id,
                claim.CellCount,
                claim.AreaM2
            });
        });

        // GET /api/territories?minLat=...&minLng=...&maxLat=...&maxLng=...
        // Get territories within a map viewport. The app calls this to draw colored hexes on the map.
        // Client sends the visible bounding box and receives all cells that intersect it.
        group.MapGet("/territories", async (
            [FromQuery] double minLat,
            [FromQuery] double minLng,
            [FromQuery] double maxLat,
            [FromQuery] double maxLng,
            AppDbContext db) =>
        {
            // Load all cells with their owner info.
            // NOTE: This loads everything into memory — acceptable for MVP scale,
            // but will need spatial indexing (PostGIS) for production at scale.
            var cells = await db.TerritoryCells
                .Include(t => t.Owner)
                .ToListAsync();

            // Filter in memory: keep only cells where at least one boundary vertex
            // falls within the requested bounding box
            var filtered = cells
                .Select(t => new
                {
                    t.CellId,
                    Boundary = t.GetBoundary(),
                    t.OwnerId,
                    OwnerColor = t.Owner!.Color,
                    OwnerName = t.Owner!.DisplayName
                })
                .Where(t => t.Boundary.Any(point =>
                    point[0] >= minLat && point[0] <= maxLat &&
                    point[1] >= minLng && point[1] <= maxLng))
                .ToList();

            return Results.Ok(filtered);
        });

        // GET /api/territories/stats/{userId}
        // Get a user's total territory stats (how many cells they currently own)
        group.MapGet("/territories/stats/{userId:guid}", async (Guid userId, AppDbContext db) =>
        {
            var cellCount = await db.TerritoryCells.CountAsync(t => t.OwnerId == userId);
            return Results.Ok(new
            {
                CellCount = cellCount,
                AreaM2 = H3Service.CalculateArea(cellCount)
            });
        });
    }

    /// <summary>
    /// Request body for submitting a new territory claim.
    /// </summary>
    /// <param name="UserId">The ID of the user making the claim.</param>
    /// <param name="Path">Array of [lat, lng] coordinate pairs representing the walked path.</param>
    public record ClaimRequest(Guid UserId, double[][] Path);

    /// <summary>
    /// Calculates the great-circle distance between two geographic points using the Haversine formula.
    /// Used to validate that the user actually walked a meaningful distance before claiming territory.
    /// </summary>
    /// <param name="lat1">Latitude of the first point in degrees.</param>
    /// <param name="lng1">Longitude of the first point in degrees.</param>
    /// <param name="lat2">Latitude of the second point in degrees.</param>
    /// <param name="lng2">Longitude of the second point in degrees.</param>
    /// <returns>The distance between the two points in meters.</returns>
    private static double HaversineMeters(double lat1, double lng1, double lat2, double lng2)
    {
        // Earth's mean radius in meters
        const double R = 6371000;
        // Convert degree deltas to radians
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLng = (lng2 - lng1) * Math.PI / 180;
        // Haversine formula: compute the square of half the chord length between the points
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(lat1 * Math.PI / 180) * Math.Cos(lat2 * Math.PI / 180) *
                Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        // Convert chord length back to arc length (distance along the sphere surface)
        return R * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }
}
