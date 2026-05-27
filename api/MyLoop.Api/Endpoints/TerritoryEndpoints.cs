using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Services;

namespace MyLoop.Api.Endpoints;

/// The core of the game — submitting a captured loop and viewing territory.
public static class TerritoryEndpoints
{
    public static void MapTerritoryEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api");

        // Submit a claim. The user walked a path and the app sent it here.
        // We figure out which hexes the path crosses through + fills inside the loop.
        // If someone else owned those hexes, tough luck — they're yours now.
        group.MapPost("/claims", async (
            [FromBody] ClaimRequest request,
            AppDbContext db) =>
        {
            // Validation: path must have enough points (at least 10 GPS readings)
            if (request.Path.Length < 10)
                return Results.BadRequest("Path too short — need at least 10 GPS points");

            // Validation: path must be at least 200 meters long (anti-abuse)
            var totalDistance = 0.0;
            for (int i = 1; i < request.Path.Length; i++)
            {
                var p1 = request.Path[i - 1];
                var p2 = request.Path[i];
                totalDistance += HaversineMeters(p1[0], p1[1], p2[0], p2[1]);
            }
            if (totalDistance < 200)
                return Results.BadRequest("Walk at least 200 meters before claiming");

            // Compute captured hexes: trail + enclosed area (if loop is closed)
            var cells = H3Service.ComputeCapturedCells(request.Path);
            if (cells.Count == 0)
                return Results.BadRequest("No hexes captured — try walking further");

            // Anti-abuse: max 5km² per claim
            var area = H3Service.CalculateArea(cells.Count);
            if (area > 5_000_000)
                return Results.BadRequest("Claim too large — max 5km² per claim");

            // Create the claim record
            var claim = new Claim
            {
                Id = Guid.NewGuid(),
                UserId = request.UserId,
                CellCount = cells.Count,
                AreaM2 = area,
            };
            claim.SetPolygon(request.Path);

            // Assign every hex inside the polygon to this user.
            // If a hex already has an owner, it gets overwritten (last-writer-wins).
            foreach (var (cellId, boundary) in cells)
            {
                var existing = await db.TerritoryCells.FindAsync(cellId);
                if (existing is not null)
                {
                    // Someone owned this hex — it's being stolen
                    existing.OwnerId = request.UserId;
                    existing.ClaimId = claim.Id;
                    existing.ClaimedAt = DateTime.UtcNow;
                    existing.SetBoundary(boundary);
                }
                else
                {
                    // Fresh hex — nobody owned it yet
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

        // Get territories within a map area. The app calls this to draw hexes on the map.
        // Send the bounding box (what's visible on screen) and get back all hexes in that area.
        group.MapGet("/territories", async (
            [FromQuery] double minLat,
            [FromQuery] double minLng,
            [FromQuery] double maxLat,
            [FromQuery] double maxLng,
            AppDbContext db) =>
        {
            // Find all cells where any boundary point falls within the bounding box.
            // This is a simple approach — good enough for MVP with a few thousand cells.
            var cells = await db.TerritoryCells
                .Include(t => t.Owner)
                .ToListAsync();

            // Filter in memory: find cells where any boundary point is in the bounding box
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

        // Get a user's total stats (how much territory they own right now)
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

    public record ClaimRequest(Guid UserId, double[][] Path);

    // Distance between two points in meters (used for path length validation)
    private static double HaversineMeters(double lat1, double lng1, double lat2, double lng2)
    {
        const double R = 6371000;
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLng = (lng2 - lng1) * Math.PI / 180;
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(lat1 * Math.PI / 180) * Math.Cos(lat2 * Math.PI / 180) *
                Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        return R * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }
}
