using H3;
using H3.Algorithms;
using H3.Extensions;
using H3.Model;
using NetTopologySuite.Geometries;

namespace MyLoop.Api.Services;

/// Converts a polygon (list of lat/lng points) into H3 hex cell IDs.
/// This is the core math of the game — it figures out which hexes
/// fall inside the loop the user walked AND which hexes the path crosses through.
public static class H3Service
{
    private const int Resolution = 10; // ~65m per hex — our chosen precision
    private const double CellAreaM2 = 4234.0; // average area of one H3 res-10 cell

    /// The main function: takes the user's path and returns ALL hexes they captured.
    /// This includes:
    /// 1. Hexes the path walked THROUGH (the trail itself)
    /// 2. Hexes enclosed INSIDE the loop (the filled area)
    /// Even a thin/straight-ish loop still captures the trail hexes.
    public static List<(long CellId, double[][] Boundary)> ComputeCapturedCells(double[][] path)
    {
        var allCells = new Dictionary<long, double[][]>();

        // Step 1: Get all hexes the path crosses through (the trail)
        var trailCells = PathToCells(path);
        foreach (var (cellId, boundary) in trailCells)
            allCells[cellId] = boundary;

        // Step 2: If the path forms a closed loop, also fill the inside
        if (IsLoopClosed(path))
        {
            var enclosedCells = PolygonFill(path);
            foreach (var (cellId, boundary) in enclosedCells)
                allCells[cellId] = boundary; // duplicates just overwrite, no harm
        }

        return allCells.Select(kv => (kv.Key, kv.Value)).ToList();
    }

    /// Check if the first and last points are close enough to form a closed loop.
    /// "Close enough" = within 50 meters of each other.
    public static bool IsLoopClosed(double[][] path)
    {
        if (path.Length < 4) return false;
        var start = path[0];
        var end = path[^1];
        var distance = HaversineMeters(start[0], start[1], end[0], end[1]);
        return distance <= 50.0;
    }

    /// Get all hexes that a path (line) crosses through.
    /// Walks along the path and samples points, getting the hex at each point.
    private static List<(long CellId, double[][] Boundary)> PathToCells(double[][] path)
    {
        var cells = new Dictionary<long, double[][]>();

        foreach (var point in path)
        {
            var index = H3Index.FromLatLng(new LatLng(point[0], point[1]), Resolution);
            var cellId = (long)(ulong)index;

            if (!cells.ContainsKey(cellId))
            {
                var boundary = index.GetCellBoundary();
                var coords = boundary.Coordinates
                    .Select(c => new double[] { c.Y, c.X })
                    .ToArray();
                cells[cellId] = coords;
            }
        }

        return cells.Select(kv => (kv.Key, kv.Value)).ToList();
    }

    /// Fill a polygon — get all hexes whose centers fall inside the closed loop.
    private static List<(long CellId, double[][] Boundary)> PolygonFill(double[][] polygon)
    {
        var coordinates = polygon
            .Select(p => new Coordinate(p[1], p[0])) // NTS uses (lng, lat) order
            .ToList();

        // Close the ring if not already closed
        if (coordinates[0] != coordinates[^1])
            coordinates.Add(coordinates[0]);

        var factory = new GeometryFactory();
        var ring = factory.CreateLinearRing(coordinates.ToArray());
        var ntsPolygon = factory.CreatePolygon(ring);

        var cells = ntsPolygon.Fill(Resolution);
        var result = new List<(long, double[][])>();

        foreach (var cell in cells)
        {
            var cellId = (long)(ulong)cell;
            var boundary = cell.GetCellBoundary();
            var coords = boundary.Coordinates
                .Select(c => new double[] { c.Y, c.X })
                .ToArray();
            result.Add((cellId, coords));
        }

        return result;
    }

    /// Calculate total area from cell count
    public static double CalculateArea(int cellCount) => cellCount * CellAreaM2;

    /// Haversine formula — distance in meters between two lat/lng points
    private static double HaversineMeters(double lat1, double lng1, double lat2, double lng2)
    {
        const double R = 6371000; // Earth radius in meters
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLng = (lng2 - lng1) * Math.PI / 180;
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(lat1 * Math.PI / 180) * Math.Cos(lat2 * Math.PI / 180) *
                Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        return R * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }
}
