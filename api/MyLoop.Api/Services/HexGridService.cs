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
/// Uses the H3 hierarchical geospatial indexing system at resolution 10.
/// </summary>
public class HexGridService : IHexGridService
{
    private readonly IGeoService _geoService;

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
            var index = H3Index.FromLatLng(new LatLng(point[0], point[1]), GameConstants.H3Resolution);
            var cellId = (long)(ulong)index;

            if (!cells.ContainsKey(cellId))
            {
                var latLng = index.ToLatLng();
                var boundary = BuildHexBoundary(latLng.LatitudeDegrees, latLng.LongitudeDegrees);
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
    /// Fills a closed polygon with all H3 cells whose centers fall inside.
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

        // Build NTS polygon and fill with H3 cells
        var factory = new GeometryFactory();
        var ring = factory.CreateLinearRing(coordinates.ToArray());
        var ntsPolygon = factory.CreatePolygon(ring);
        var cells = ntsPolygon.Fill(GameConstants.H3Resolution);

        var result = new List<HexCell>();
        foreach (var cell in cells)
        {
            var cellId = (long)(ulong)cell;
            var latLng = cell.ToLatLng();
            var boundary = BuildHexBoundary(latLng.LatitudeDegrees, latLng.LongitudeDegrees);
            result.Add(new HexCell { CellId = cellId, Boundary = boundary });
        }
        return result;
    }

    /// <summary>
    /// Builds a visually-perfect regular hexagon for map display.
    /// Uses latitude-corrected radius so hexes look uniform at any latitude.
    /// </summary>
    private static double[][] BuildHexBoundary(double centerLat, double centerLng)
    {
        double radiusMeters = GameConstants.HexVisualRadiusMeters;
        double metersPerDegreeLat = GameConstants.MetersPerDegreeLat;
        var metersPerDegreeLng = metersPerDegreeLat * Math.Cos(centerLat * Math.PI / 180.0);

        var latRadius = radiusMeters / metersPerDegreeLat;
        var lngRadius = radiusMeters / metersPerDegreeLng;

        // 6 vertices of a flat-top hexagon at 0°, 60°, 120°, 180°, 240°, 300°
        var vertices = new double[7][];
        for (int i = 0; i < 6; i++)
        {
            var angleRad = (60.0 * i) * Math.PI / 180.0;
            vertices[i] = new double[]
            {
                centerLat + latRadius * Math.Cos(angleRad),
                centerLng + lngRadius * Math.Sin(angleRad)
            };
        }

        // Close the polygon
        vertices[6] = vertices[0];
        return vertices;
    }
}
