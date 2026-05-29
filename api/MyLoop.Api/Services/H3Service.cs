using H3;
using H3.Algorithms;
using H3.Extensions;
using H3.Model;
using NetTopologySuite.Geometries;

namespace MyLoop.Api.Services;

/// <summary>
/// H3 hexagonal grid service — converts GPS paths and polygons into discrete H3 hex cell IDs.
/// This is the core spatial math of the game: it determines which hexagons a user's walked path
/// crosses through, and which hexagons are enclosed inside a closed loop.
/// Uses Uber's H3 hierarchical geospatial indexing system at resolution 10 (~65m hexagons).
/// </summary>
public static class H3Service
{
    /// <summary>H3 resolution level. Resolution 10 yields hexagons approximately 65m across.</summary>
    private const int Resolution = 10;

    /// <summary>Average area in square meters of a single H3 resolution-10 cell (~4,234 m²).</summary>
    private const double CellAreaM2 = 4234.0;

    /// <summary>
    /// Computes all hexagonal cells captured by the user's walked path.
    /// Combines two strategies:
    /// <list type="number">
    ///   <item><description>Trail cells — hexes the GPS path physically passes through.</description></item>
    ///   <item><description>Fill cells — hexes enclosed inside the loop (only if the path is closed).</description></item>
    /// </list>
    /// Even a non-closed path still captures the trail cells along the walked route.
    /// </summary>
    /// <param name="path">Array of [latitude, longitude] coordinate pairs from GPS readings.</param>
    /// <returns>List of captured cells, each with its H3 cell ID and boundary polygon coordinates.</returns>
    public static List<(long CellId, double[][] Boundary)> ComputeCapturedCells(double[][] path)
    {
        var allCells = new Dictionary<long, double[][]>();

        // Step 1: Get all hexes the path physically crosses through (the trail)
        var trailCells = PathToCells(path);
        foreach (var (cellId, boundary) in trailCells)
            allCells[cellId] = boundary;

        // Step 2: If the path forms a closed loop (start ≈ end), also fill the enclosed interior
        if (IsLoopClosed(path))
        {
            var enclosedCells = PolygonFill(path);
            foreach (var (cellId, boundary) in enclosedCells)
                allCells[cellId] = boundary; // duplicates just overwrite — no harm done
        }

        return allCells.Select(kv => (kv.Key, kv.Value)).ToList();
    }

    /// <summary>
    /// Determines whether a path forms a closed loop by checking if the first and last
    /// points are within 50 meters of each other (the "snap-to-close" threshold).
    /// </summary>
    /// <param name="path">Array of [latitude, longitude] coordinate pairs.</param>
    /// <returns><c>true</c> if the path endpoints are within 50m; otherwise <c>false</c>.</returns>
    public static bool IsLoopClosed(double[][] path)
    {
        if (path.Length < 4) return false; // minimum 4 points needed to form any polygon
        var start = path[0];
        var end = path[^1];
        var distance = HaversineMeters(start[0], start[1], end[0], end[1]);
        return distance <= 50.0; // 50m closure threshold
    }

    /// <summary>
    /// Converts a GPS path (polyline) into the set of H3 cells it passes through.
    /// Each GPS point is mapped to its containing hex; duplicates are deduplicated.
    /// </summary>
    /// <param name="path">Array of [latitude, longitude] coordinate pairs.</param>
    /// <returns>List of unique cells along the path, each with ID and boundary coordinates.</returns>
    private static List<(long CellId, double[][] Boundary)> PathToCells(double[][] path)
    {
        var cells = new Dictionary<long, double[][]>();

        foreach (var point in path)
        {
            // Convert the lat/lng point to an H3 index at our chosen resolution
            var index = H3Index.FromLatLng(new LatLng(point[0], point[1]), Resolution);
            // Cast the H3Index to a 64-bit integer for storage in the database
            var cellId = (long)(ulong)index;

            if (!cells.ContainsKey(cellId))
            {
                // Retrieve the hexagon's 6 corner vertices for rendering on the map
                var boundary = index.GetCellBoundary();
                // Convert from NTS Coordinate (X=lng, Y=lat) to our [lat, lng] format
                var coords = boundary.Coordinates
                    .Select(c => new double[] { c.Y, c.X })
                    .ToArray();
                cells[cellId] = coords;
            }
        }

        return cells.Select(kv => (kv.Key, kv.Value)).ToList();
    }

    /// <summary>
    /// Fills a closed polygon with all H3 cells whose centers fall inside the boundary.
    /// Uses the H3 library's polyfill algorithm via NetTopologySuite geometry.
    /// </summary>
    /// <param name="polygon">Array of [latitude, longitude] coordinate pairs forming a closed ring.</param>
    /// <returns>List of all cells enclosed within the polygon.</returns>
    private static List<(long CellId, double[][] Boundary)> PolygonFill(double[][] polygon)
    {
        // Convert [lat, lng] to NTS Coordinate (which expects lng, lat order)
        var coordinates = polygon
            .Select(p => new Coordinate(p[1], p[0]))
            .ToList();

        // Ensure the ring is closed (first point == last point) as required by NTS
        if (coordinates[0] != coordinates[^1])
            coordinates.Add(coordinates[0]);

        // Build a NTS polygon and use the H3 Fill extension to get all interior cells
        var factory = new GeometryFactory();
        var ring = factory.CreateLinearRing(coordinates.ToArray());
        var ntsPolygon = factory.CreatePolygon(ring);

        // H3 polyfill: returns all cell indexes whose centers lie within the polygon
        var cells = ntsPolygon.Fill(Resolution);
        var result = new List<(long, double[][])>();

        foreach (var cell in cells)
        {
            var cellId = (long)(ulong)cell;
            var boundary = cell.GetCellBoundary();
            // Convert boundary vertices back to [lat, lng] format for client rendering
            var coords = boundary.Coordinates
                .Select(c => new double[] { c.Y, c.X })
                .ToArray();
            result.Add((cellId, coords));
        }

        return result;
    }

    /// <summary>
    /// Calculates the approximate total area represented by a number of H3 cells.
    /// </summary>
    /// <param name="cellCount">The number of H3 resolution-10 cells.</param>
    /// <returns>Total area in square meters.</returns>
    public static double CalculateArea(int cellCount) => cellCount * CellAreaM2;

    /// <summary>H3 resolution used for parent cell grouping (spatial hash buckets, ~12km zones).</summary>
    private const int ParentResolution = 3;

    /// <summary>
    /// Gets the center latitude and longitude of an H3 cell.
    /// Used to populate CenterLat/CenterLng for spatial viewport queries.
    /// </summary>
    /// <param name="cellId">The H3 cell ID as a 64-bit integer.</param>
    /// <returns>Tuple of (latitude, longitude) in degrees.</returns>
    public static (double Lat, double Lng) GetCellCenter(long cellId)
    {
        var index = (H3Index)(ulong)cellId;
        var latLng = index.ToLatLng();
        return (latLng.LatitudeDegrees, latLng.LongitudeDegrees);
    }

    /// <summary>
    /// Gets the H3 parent cell ID at resolution 3 for a given resolution-10 cell.
    /// Parent cells act as spatial hash buckets (~12km zones) for partition pruning.
    /// </summary>
    /// <param name="cellId">The H3 resolution-10 cell ID.</param>
    /// <returns>The H3 resolution-3 parent cell ID.</returns>
    public static long GetParentCellId(long cellId)
    {
        var index = (H3Index)(ulong)cellId;
        var parent = index.GetParentForResolution(ParentResolution);
        return (long)(ulong)parent;
    }

    /// <summary>
    /// Computes the great-circle distance between two geographic points using the Haversine formula.
    /// Used internally to check loop closure (whether start and end points are within threshold).
    /// </summary>
    /// <param name="lat1">Latitude of the first point in degrees.</param>
    /// <param name="lng1">Longitude of the first point in degrees.</param>
    /// <param name="lat2">Latitude of the second point in degrees.</param>
    /// <param name="lng2">Longitude of the second point in degrees.</param>
    /// <returns>Distance between the two points in meters.</returns>
    private static double HaversineMeters(double lat1, double lng1, double lat2, double lng2)
    {
        const double R = 6371000; // Earth's mean radius in meters
        // Convert latitude/longitude deltas from degrees to radians
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLng = (lng2 - lng1) * Math.PI / 180;
        // Haversine formula: 'a' is the square of half the chord length between the two points
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(lat1 * Math.PI / 180) * Math.Cos(lat2 * Math.PI / 180) *
                Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        // Convert from chord length to arc length on the sphere surface
        return R * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }
}
