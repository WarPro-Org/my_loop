using H3;
using H3.Algorithms;
using H3.Extensions;
using H3.Model;
using MyLoop.Api.Constants;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using System.Text.Json;

namespace MyLoop.Api.Services;

/// <summary>
/// Seeds hex territory for bot users so day-1 players have competition.
/// Generates organic-looking hex clusters around city centers.
/// </summary>
public static class TerritorySeedService
{
    private static readonly Random Rng = new(42); // deterministic seed for reproducibility

    /// <summary>
    /// City centers used for territory seeding.
    /// </summary>
    private static readonly Dictionary<string, (double Lat, double Lng)> CityCenters = new()
    {
        ["Bangalore"] = (12.9716, 77.5946),
        ["Mumbai"] = (19.0760, 72.8777),
        ["Delhi"] = (28.6139, 77.2090),
        ["London"] = (51.5074, -0.1278),
        ["New York"] = (40.7128, -74.0060),
        ["Tokyo"] = (35.6762, 139.6503),
    };

    /// <summary>
    /// Seeds territory for all bot users that don't already have cells.
    /// Call once during startup if TerritoryCells table is empty.
    /// </summary>
    public static void SeedBotTerritory(AppDbContext db, List<User> users)
    {
        var claimsBatch = new List<Claim>();
        var cellsBatch = new List<TerritoryCell>();

        foreach (var user in users)
        {
            if (!CityCenters.TryGetValue(user.City, out var center)) continue;
            if (user.HexCount <= 0) continue;

            // Generate hex clusters proportional to user's HexCount (capped for performance)
            var targetCells = Math.Min(user.HexCount, 200);
            var clusterCount = Math.Max(1, targetCells / 15);

            var claim = new Claim
            {
                Id = Guid.NewGuid(),
                UserId = user.Id,
                CellCount = 0,
                AreaM2 = 0,
                CreatedAt = user.CreatedAt.AddHours(Rng.Next(1, 72)),
                PolygonJson = "[]",
            };

            var generatedCells = GenerateClusters(user.Id, claim.Id, center, clusterCount, targetCells);

            claim.CellCount = generatedCells.Count;
            claim.AreaM2 = generatedCells.Count * GameConstants.CellAreaSquareMeters;

            claimsBatch.Add(claim);
            cellsBatch.AddRange(generatedCells);
        }

        // Resolve conflicts — if multiple bots claim the same cell, last one wins
        var dedupedCells = cellsBatch
            .GroupBy(c => c.CellId)
            .Select(g => g.Last())
            .ToList();

        db.Claims.AddRange(claimsBatch);
        db.TerritoryCells.AddRange(dedupedCells);
        db.SaveChanges();

        // Update user hex counts to reflect actual seeded territory
        foreach (var user in users)
        {
            var actualCount = dedupedCells.Count(c => c.OwnerId == user.Id);
            if (actualCount > 0)
            {
                user.HexCount = actualCount;
                user.TotalHexesCaptured = actualCount;
            }
        }
        db.SaveChanges();
    }

    private static List<TerritoryCell> GenerateClusters(
        Guid ownerId, Guid claimId, (double Lat, double Lng) center,
        int clusterCount, int targetCells)
    {
        var cells = new Dictionary<long, TerritoryCell>();
        var cellsPerCluster = targetCells / clusterCount;

        for (int i = 0; i < clusterCount && cells.Count < targetCells; i++)
        {
            // Random offset from city center (within ~2km radius)
            var offsetLat = (Rng.NextDouble() - 0.5) * 0.036; // ~2km
            var offsetLng = (Rng.NextDouble() - 0.5) * 0.036;
            var clusterCenter = (center.Lat + offsetLat, center.Lng + offsetLng);

            // Get the H3 cell at this point
            var latRad = clusterCenter.Item1 * Math.PI / 180.0;
            var lngRad = clusterCenter.Item2 * Math.PI / 180.0;
            var centerIndex = H3Index.FromLatLng(new LatLng(latRad, lngRad), GameConstants.H3Resolution);

            // Use kRing to get a natural hex cluster
            var ringSize = (int)Math.Ceiling(Math.Sqrt(cellsPerCluster));
            var ring = centerIndex.GridDiskDistances(ringSize);

            foreach (var ringCell in ring)
            {
                if (cells.Count >= targetCells) break;
                var hex = ringCell.Index;
                var cellId = (long)(ulong)hex;
                if (cells.ContainsKey(cellId)) continue;

                var boundary = GetBoundary(hex);
                var cellCenter = hex.ToLatLng();

                var parentLatRad = cellCenter.LatitudeDegrees * Math.PI / 180.0;
                var parentLngRad = cellCenter.LongitudeDegrees * Math.PI / 180.0;
                var parentIndex = H3Index.FromLatLng(new LatLng(parentLatRad, parentLngRad), GameConstants.H3ParentResolution);
                var neighborhoodIndex = H3Index.FromLatLng(new LatLng(parentLatRad, parentLngRad), GameConstants.H3NeighborhoodResolution);

                cells[cellId] = new TerritoryCell
                {
                    CellId = cellId,
                    OwnerId = ownerId,
                    ClaimId = claimId,
                    ClaimedAt = DateTime.UtcNow.AddDays(-Rng.Next(1, 30)),
                    CooldownExpiresAt = null, // no cooldown for seeded cells
                    CenterLat = cellCenter.LatitudeDegrees,
                    CenterLng = cellCenter.LongitudeDegrees,
                    ParentCellId = (long)(ulong)parentIndex,
                    NeighborhoodId = (long)(ulong)neighborhoodIndex,
                    BoundaryJson = JsonSerializer.Serialize(boundary),
                };
            }
        }

        return cells.Values.ToList();
    }

    private static double[][] GetBoundary(H3Index index)
    {
        var factory = new NetTopologySuite.Geometries.GeometryFactory();
        var polygon = index.GetCellBoundary(factory);
        var coords = polygon.ExteriorRing.Coordinates;
        var vertices = new double[coords.Length][];
        for (int i = 0; i < coords.Length; i++)
        {
            vertices[i] = [coords[i].Y, coords[i].X]; // [lat, lng]
        }
        return vertices;
    }
}
