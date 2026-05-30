using H3;
using H3.Algorithms;
using H3.Extensions;
using H3.Model;
using NetTopologySuite.Geometries;

Console.WriteLine("=== H3 Resolution 11 Fill Test ===\n");

// Simulate the user's actual walk loop (~200m x 180m)
var path = new double[][] {
    [59.3065, 18.0670], [59.3067, 18.0675], [59.3069, 18.0680],
    [59.3071, 18.0685], [59.3073, 18.0688], [59.3075, 18.0690],
    [59.3077, 18.0688], [59.3079, 18.0685], [59.3080, 18.0680],
    [59.3079, 18.0675], [59.3077, 18.0670], [59.3075, 18.0665],
    [59.3073, 18.0662], [59.3071, 18.0660], [59.3069, 18.0662],
    [59.3067, 18.0665], [59.3065, 18.0668], [59.3065, 18.0670],
};

const int resolution = 11;
const double hexApothemMeters = 25.0;
const double metersPerDegreeLat = 111320.0;

// 1. Trail cells
var trailCells = new HashSet<long>();
foreach (var point in path)
{
    var latRad = point[0] * Math.PI / 180.0;
    var lngRad = point[1] * Math.PI / 180.0;
    var index = H3Index.FromLatLng(new LatLng(latRad, lngRad), resolution);
    trailCells.Add((long)(ulong)index);
}
Console.WriteLine($"Trail cells: {trailCells.Count}");

// 2. Fill polygon
var coordinates = path.Select(p => new Coordinate(p[1], p[0])).ToList();
coordinates.Add(coordinates[0]); // close ring
var factory = new GeometryFactory();
var ring = factory.CreateLinearRing(coordinates.ToArray());
var polygon = factory.CreatePolygon(ring);

// Calculate area
var centLat = path.Average(p => p[0]);
var centLng = path.Average(p => p[1]);
var metersPerDegreeLng = metersPerDegreeLat * Math.Cos(centLat * Math.PI / 180.0);
double area = 0;
for (int i = 0; i < path.Length; i++)
{
    var j = (i + 1) % path.Length;
    var xi = (path[i][1] - centLng) * metersPerDegreeLng;
    var yi = (path[i][0] - centLat) * metersPerDegreeLat;
    var xj = (path[j][1] - centLng) * metersPerDegreeLng;
    var yj = (path[j][0] - centLat) * metersPerDegreeLat;
    area += xi * yj - xj * yi;
}
area = Math.Abs(area) / 2.0;
Console.WriteLine($"Polygon area: {area:F0} m²");

// Buffer + fill
var bufferDegrees = hexApothemMeters / metersPerDegreeLat;
var buffered = polygon.Buffer(bufferDegrees);
var fillCells = buffered.Fill(resolution).ToList();
Console.WriteLine($"Fill cells (buffered): {fillCells.Count}");

// Without buffer
var fillNoBuf = polygon.Fill(resolution).ToList();
Console.WriteLine($"Fill cells (no buffer): {fillNoBuf.Count}");

// Total unique
var allCells = new HashSet<long>(trailCells);
foreach (var cell in fillCells) allCells.Add((long)(ulong)cell);
Console.WriteLine($"\nTOTAL unique cells: {allCells.Count}");
Console.WriteLine($"  Trail only: {trailCells.Count}");
Console.WriteLine($"  Fill interior: {fillNoBuf.Count}");
Console.WriteLine($"  Fill + boundary: {fillCells.Count}");

// Verify boundary extraction
var sampleCell = fillCells[0];
var boundary = sampleCell.GetCellBoundary(factory);
Console.WriteLine($"\nBoundary test (first fill cell):");
Console.WriteLine($"  Vertices: {boundary.ExteriorRing.Coordinates.Length} (should be 7 = 6+close)");
Console.WriteLine($"  First vertex: ({boundary.ExteriorRing.Coordinates[0].Y:F6}, {boundary.ExteriorRing.Coordinates[0].X:F6})");
