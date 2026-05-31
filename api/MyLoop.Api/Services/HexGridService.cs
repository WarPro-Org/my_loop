using H3;
using H3.Algorithms;
using H3.Extensions;
using H3.Model;
using NetTopologySuite.Geometries;
using NetTopologySuite.Geometries.Utilities;
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

        // Step 1: Trail cells — hexes the GPS path physically crosses
        var trailCells = GetTrailCells(path);
        foreach (var cell in trailCells)
        {
            allCells[cell.CellId] = cell.Boundary;
        }

        // Step 2: Extract ALL closed loops, deduplicate, and fill
        var loops = ExtractLoops(path);
        if (loops.Count == 0) goto done;

        // Convert each loop to a repaired NTS polygon (skip ones that fail or are too small)
        var ntsPolygons = new List<Geometry>();
        foreach (var loop in loops)
        {
            // Skip loops too small to contain hex cells (< 5000 m²)
            var loopArea = _geoService.CalculatePolygonArea(loop);
            if (loopArea < GameConstants.MinFillAreaSquareMeters) continue;

            var poly = BuildRepairedPolygon(loop);
            if (poly != null && !poly.IsEmpty && poly.Area > 0)
                ntsPolygons.Add(poly);
        }
        if (ntsPolygons.Count == 0) goto done;

        // Deduplicate: merge polygons that overlap >80% (same loop walked multiple times)
        var uniquePolygons = DeduplicatePolygons(ntsPolygons);

        // Process each loop independently: fill interior + 51% boundary check PER LOOP.
        // The 51% rule is per-loop only — no cross-loop accumulation.
        // You must loop around >51% of a hex in a SINGLE loop to capture it.
        // This prevents the exploit of clipping a hex from multiple angles without
        // ever meaningfully encircling it.
        foreach (var poly in uniquePolygons)
        {
            try
            {
                // Phase 1: Interior fill — cells whose center is inside this loop
                var interiorCells = poly.Fill(GameConstants.H3Resolution).ToList();
                var interiorSet = new HashSet<ulong>(interiorCells.Select(c => (ulong)c));

                // Add interior cells
                foreach (var cell in interiorCells)
                {
                    var id = (long)(ulong)cell;
                    if (!allCells.ContainsKey(id))
                    {
                        var boundary = GetRealCellBoundary(cell);
                        allCells[id] = boundary;
                    }
                }

                // Phase 2: Boundary cells — ring-1 neighbors checked against THIS loop only
                var boundaryCandidates = new HashSet<ulong>();
                foreach (var cell in interiorCells)
                {
                    foreach (var ringCell in cell.GridDiskDistances(1))
                    {
                        var neighborId = (ulong)ringCell.Index;
                        if (!interiorSet.Contains(neighborId) && !allCells.ContainsKey((long)neighborId))
                        {
                            boundaryCandidates.Add(neighborId);
                        }
                    }
                }

                // Parallel 51% intersection check against THIS loop's polygon
                var qualifiedBoundary = new System.Collections.Concurrent.ConcurrentBag<ulong>();
                Parallel.ForEach(boundaryCandidates, candidateId =>
                {
                    try
                    {
                        var candidate = (H3Index)candidateId;
                        var cellPolygon = candidate.GetCellBoundary(_geometryFactory);
                        var intersection = poly.Intersection(cellPolygon);
                        var ratio = intersection.Area / cellPolygon.Area;
                        if (ratio >= GameConstants.MinIntersectionRatio)
                        {
                            qualifiedBoundary.Add(candidateId);
                        }
                    }
                    catch (TopologyException) { /* Skip ambiguous boundary cells */ }
                });

                foreach (var cellId in qualifiedBoundary)
                {
                    var id = (long)cellId;
                    if (!allCells.ContainsKey(id))
                    {
                        var boundary = GetRealCellBoundary((H3Index)cellId);
                        allCells[id] = boundary;
                    }
                }
            }
            catch { /* Skip loops that fail entirely */ }
        }

        done:
        // Convert dictionary to list
        var result = new List<HexCell>(allCells.Count);
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
    /// Converts a GPS loop (lat/lng points) into a repaired NTS polygon.
    /// Applies Buffer(0) to fix self-intersections from GPS noise.
    /// Returns null if the polygon can't be built or has zero area.
    /// </summary>
    private static Geometry? BuildRepairedPolygon(double[][] loop)
    {
        if (loop.Length < 4) return null;

        var coordinates = loop
            .Select(p => new Coordinate(p[1], p[0]))
            .ToList();

        // Ensure the ring is closed as required by NTS
        if (coordinates[0] != coordinates[^1])
            coordinates.Add(coordinates[0]);

        try
        {
            var ring = _geometryFactory.CreateLinearRing(coordinates.ToArray());
            var rawPolygon = _geometryFactory.CreatePolygon(ring);

            // ALWAYS repair — GPS trails routinely have self-intersections
            Geometry repaired;
            try { repaired = rawPolygon.Buffer(0); }
            catch { repaired = GeometryFixer.Fix(rawPolygon); }

            if (repaired.IsEmpty || repaired.Area == 0) return null;
            return repaired;
        }
        catch { return null; }
    }

    /// <summary>
    /// Deduplicates polygons that overlap significantly (>80% shared area).
    /// Walking the same loop 100 times produces ~100 nearly-identical polygons;
    /// we keep only the largest variant. Different loops (figure-8 halves) are kept separate.
    /// </summary>
    private static List<Geometry> DeduplicatePolygons(List<Geometry> polygons)
    {
        if (polygons.Count <= 1) return polygons;

        // Sort by area descending — larger polygons take priority
        var sorted = polygons.OrderByDescending(p => p.Area).ToList();
        var kept = new List<Geometry>();

        foreach (var candidate in sorted)
        {
            var isDuplicate = false;
            foreach (var existing in kept)
            {
                try
                {
                    var intersection = existing.Intersection(candidate);
                    var overlapRatio = intersection.Area / candidate.Area;
                    if (overlapRatio > 0.80)
                    {
                        isDuplicate = true;
                        break;
                    }
                }
                catch (TopologyException) { /* Can't compare — keep it */ }
            }

            if (!isDuplicate)
                kept.Add(candidate);
        }

        return kept;
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
