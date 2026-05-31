using H3;
using H3.Algorithms;
using H3.Extensions;
using H3.Model;
using NetTopologySuite.Geometries;
using MyLoop.Api.Constants;
using MyLoop.Api.Models;

namespace MyLoop.Api.Services;

/// <summary>
/// Hex grid operations — converts GPS data into H3 hex cells.
/// Uses the H3 hierarchical geospatial indexing system at resolution 11.
/// All boundaries are real H3 cell polygons (not fabricated), so hexes
/// tessellate edge-to-edge on the map with no gaps.
/// </summary>
public class HexGridService : IHexGridService
{
    private readonly IGeoService _geoService;
    private static readonly GeometryFactory _geometryFactory = new();

    public HexGridService(IGeoService geoService)
    {
        _geoService = geoService;
    }

    public List<HexCell> ComputeCapturedCells(double[][] path)
    {
        var allCells = new Dictionary<long, double[][]>();

        // Step 1: Get hexes the path physically crosses (trail cells)
        var trailCells = GetTrailCells(path);
        foreach (var cell in trailCells)
        {
            allCells[cell.CellId] = cell.Boundary;
        }

        // Step 2: Extract ALL closed loops from the path and fill each one.
        // A single walk can produce multiple loops (figure-8, laps, etc.)
        var loops = ExtractLoops(path);
        foreach (var loop in loops)
        {
            var polygonArea = _geoService.CalculatePolygonArea(loop);
            if (polygonArea >= GameConstants.MinFillAreaSquareMeters)
            {
                var fillCells = FillPolygon(loop);
                foreach (var cell in fillCells)
                {
                    allCells[cell.CellId] = cell.Boundary;
                }
            }
        }

        // Convert dictionary to list of HexCell objects
        var result = new List<HexCell>();
        foreach (var pair in allCells)
        {
            result.Add(new HexCell { CellId = pair.Key, Boundary = pair.Value });
        }
        return result;
    }

    public GeoCoordinate GetCellCenter(long cellId)
    {
        var index = (H3Index)(ulong)cellId;
        var latLng = index.ToLatLng();
        return new GeoCoordinate
        {
            Lat = latLng.LatitudeDegrees,
            Lng = latLng.LongitudeDegrees
        };
    }

    public long GetParentCellId(long cellId)
    {
        var index = (H3Index)(ulong)cellId;
        var parent = index.GetParentForResolution(GameConstants.H3ParentResolution);
        return (long)(ulong)parent;
    }

    public double CalculateArea(int cellCount)
    {
        return cellCount * GameConstants.CellAreaSquareMeters;
    }

    // --- Private helpers ---

    /// <summary>
    /// Extracts all closed loops from a GPS trail using spatial proximity.
    /// Walks the path and detects when the trail crosses back near a previous point
    /// (within LoopClosureDistanceMeters). Each detected loop is extracted as a
    /// sub-polygon. Handles figure-8s, multiple laps, overlapping loops, etc.
    /// Returns loops ordered largest-area-first.
    /// </summary>
    private List<double[][]> ExtractLoops(double[][] path)
    {
        if (path.Length < 4) return [];

        var loops = new List<double[][]>();
        var closureThreshold = GameConstants.LoopClosureDistanceMeters;

        // Use a spatial index approach: for each point, check if it's close to
        // any EARLIER point (skipping immediate neighbors to avoid false positives).
        // When a closure is found, extract that sub-path as a loop.
        // Mark used points to avoid double-counting the same loop.
        const int minLoopPoints = 20; // Need at least 20 GPS points for a meaningful loop
        const int skipNeighbors = 10; // Don't compare to immediate neighbors (would find tiny "loops" from GPS jitter)

        var used = new bool[path.Length];

        for (int i = skipNeighbors; i < path.Length; i++)
        {
            if (used[i]) continue;

            for (int j = 0; j <= i - minLoopPoints; j++)
            {
                if (used[j]) continue;

                var dist = _geoService.HaversineMeters(
                    path[i][0], path[i][1],
                    path[j][0], path[j][1]);

                if (dist <= closureThreshold)
                {
                    // Found a loop from j to i
                    var loopLength = i - j + 1;
                    var loop = new double[loopLength][];
                    Array.Copy(path, j, loop, 0, loopLength);

                    loops.Add(loop);

                    // Mark points in this loop as used so we don't re-detect it
                    for (int k = j; k <= i; k++)
                        used[k] = true;

                    break; // Move on from point i — we found its closure
                }
            }
        }

        // Also check the simple start≈end case (entire path is one loop)
        // Only add if we didn't already extract it
        if (loops.Count == 0 && IsLoopClosed(path))
        {
            loops.Add(path);
        }

        // Sort largest area first (most valuable loops processed first)
        loops.Sort((a, b) =>
            _geoService.CalculatePolygonArea(b).CompareTo(_geoService.CalculatePolygonArea(a)));

        return loops;
    }

    /// <summary>
    /// Checks if the path forms a closed loop (start within 50m of end).
    /// </summary>
    private bool IsLoopClosed(double[][] path)
    {
        if (path.Length < 4) return false;
        var start = path[0];
        var end = path[^1];
        var distance = _geoService.HaversineMeters(start[0], start[1], end[0], end[1]);
        return distance <= GameConstants.LoopClosureDistanceMeters;
    }

    /// <summary>
    /// Gets all hex cells the GPS path passes through (trail cells).
    /// </summary>
    private List<HexCell> GetTrailCells(double[][] path)
    {
        var cells = new Dictionary<long, double[][]>();

        foreach (var point in path)
        {
            // H3's LatLng expects radians, not degrees
            var latRad = point[0] * Math.PI / 180.0;
            var lngRad = point[1] * Math.PI / 180.0;
            var index = H3Index.FromLatLng(new LatLng(latRad, lngRad), GameConstants.H3Resolution);
            var cellId = (long)(ulong)index;

            if (!cells.ContainsKey(cellId))
            {
                var boundary = GetRealCellBoundary(index);
                cells[cellId] = boundary;
            }
        }

        var result = new List<HexCell>();
        foreach (var pair in cells)
        {
            result.Add(new HexCell { CellId = pair.Key, Boundary = pair.Value });
        }
        return result;
    }

    /// <summary>
    /// Fills a closed polygon with H3 cells using exact geometric intersection.
    /// Step 1: All cells whose centers are fully inside the polygon (interior cluster).
    /// Step 2: Boundary candidates (ring-1 neighbors) included if ≥51% of cell area overlaps.
    /// Uses parallel computation for the intersection checks.
    /// </summary>
    private List<HexCell> FillPolygon(double[][] polygon)
    {
        // Convert [lat, lng] to NTS Coordinate format (lng, lat)
        var coordinates = polygon
            .Select(p => new Coordinate(p[1], p[0]))
            .ToList();

        // Ensure the ring is closed as required by NTS
        if (coordinates[0] != coordinates[^1])
        {
            coordinates.Add(coordinates[0]);
        }

        // Build NTS polygon
        var ring = _geometryFactory.CreateLinearRing(coordinates.ToArray());
        var rawPolygon = _geometryFactory.CreatePolygon(ring);

        // ALWAYS repair — GPS trails routinely have self-intersections from noise.
        // Buffer(0) is the standard NTS trick to fix topology; GeometryFixer is fallback.
        NetTopologySuite.Geometries.Geometry ntsPolygon;
        try { ntsPolygon = rawPolygon.Buffer(0); }
        catch { ntsPolygon = NetTopologySuite.Geometries.Utilities.GeometryFixer.Fix(rawPolygon); }
        if (ntsPolygon.IsEmpty || ntsPolygon.Area == 0)
            return [];

        // Step 1: Fill interior — all cells whose center is inside the polygon
        var interiorCells = ntsPolygon.Fill(GameConstants.H3Resolution).ToList();
        var interiorSet = new HashSet<ulong>(interiorCells.Select(c => (ulong)c));

        // Step 2: Find boundary candidates — ring-1 neighbors of interior cells
        // that are NOT already in the interior set
        var boundaryCandidates = new HashSet<ulong>();
        foreach (var cell in interiorCells)
        {
            foreach (var ringCell in cell.GridDiskDistances(1))
            {
                var id = (ulong)ringCell.Index;
                if (!interiorSet.Contains(id))
                {
                    boundaryCandidates.Add(id);
                }
            }
        }

        // Step 3: Parallel intersection check — include boundary cells with ≥51% overlap
        // Wrap in try/catch: NTS overlay can still fail on edge-case geometries.
        // Cells that fail are marginal boundary cells — safe to skip.
        var qualifiedBoundary = new System.Collections.Concurrent.ConcurrentBag<H3Index>();
        Parallel.ForEach(boundaryCandidates, candidateId =>
        {
            try
            {
                var candidate = (H3Index)candidateId;
                var cellPolygon = candidate.GetCellBoundary(_geometryFactory);
                var intersection = ntsPolygon.Intersection(cellPolygon);
                var ratio = intersection.Area / cellPolygon.Area;
                if (ratio >= GameConstants.MinIntersectionRatio)
                {
                    qualifiedBoundary.Add(candidate);
                }
            }
            catch (NetTopologySuite.Geometries.TopologyException)
            {
                // Skip this boundary cell — overlap was ambiguous anyway
            }
        });

        // Combine interior + qualified boundary cells
        var result = new List<HexCell>(interiorCells.Count + qualifiedBoundary.Count);
        foreach (var cell in interiorCells)
        {
            var cellId = (long)(ulong)cell;
            var boundary = GetRealCellBoundary(cell);
            result.Add(new HexCell { CellId = cellId, Boundary = boundary });
        }
        foreach (var cell in qualifiedBoundary)
        {
            var cellId = (long)(ulong)cell;
            var boundary = GetRealCellBoundary(cell);
            result.Add(new HexCell { CellId = cellId, Boundary = boundary });
        }
        return result;
    }

    /// <summary>
    /// Gets the REAL H3 cell boundary polygon vertices.
    /// Returns the actual hex corners from the H3 library, ensuring cells
    /// tessellate perfectly edge-to-edge with no gaps on the map.
    /// </summary>
    private static double[][] GetRealCellBoundary(H3Index index)
    {
        var polygon = index.GetCellBoundary(_geometryFactory);
        var coords = polygon.ExteriorRing.Coordinates;

        // NTS coordinates are (X=lng, Y=lat). Convert to [lat, lng] format.
        var vertices = new double[coords.Length][];
        for (int i = 0; i < coords.Length; i++)
        {
            vertices[i] = [coords[i].Y, coords[i].X];
        }
        return vertices;
    }
}
