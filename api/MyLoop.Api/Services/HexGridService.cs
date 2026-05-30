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

        // Step 2: If the path is a closed loop, fill the enclosed area
        if (IsLoopClosed(path))
        {
            var polygonArea = _geoService.CalculatePolygonArea(path);
            if (polygonArea >= GameConstants.MinFillAreaSquareMeters)
            {
                var fillCells = FillPolygon(path);
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
    /// Fills a closed polygon with all H3 cells whose centers fall inside,
    /// PLUS boundary cells that are at least ~50% inside the polygon.
    /// Buffers the polygon outward by the hex apothem before filling.
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
        var ntsPolygon = _geometryFactory.CreatePolygon(ring);

        // Buffer outward by the hex apothem (~25m at res 11) in degrees.
        // This captures cells whose center is within one apothem of the edge,
        // meaning the cell is approximately ≥50% inside the loop.
        var bufferDegrees = GameConstants.HexApothemMeters / GameConstants.MetersPerDegreeLat;
        var bufferedPolygon = ntsPolygon.Buffer(bufferDegrees);

        // Fill the buffered polygon with H3 cells
        var cells = bufferedPolygon.Fill(GameConstants.H3Resolution);

        var result = new List<HexCell>();
        foreach (var cell in cells)
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
