using H3;
using H3.Algorithms;
using H3.Extensions;
using H3.Model;
using NetTopologySuite.Geometries;
using System.Text.Json;

Console.WriteLine("-- H3 Res 11 cluster INSERT for Parth (Stockholm 59.3072, 18.068)");

const int resolution = 11;
var factory = new GeometryFactory();
var userId = "63f7974c-ccbd-4601-9707-c2efeabed96c";
var claimId = Guid.NewGuid().ToString();
var now = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss+00");
var cooldown = DateTime.UtcNow.AddHours(5).ToString("yyyy-MM-dd HH:mm:ss+00");

// Get center cell + ring-1 neighbors = 7 cells (nice cluster)
var centerLatRad = 59.3072 * Math.PI / 180.0;
var centerLngRad = 18.0680 * Math.PI / 180.0;
var centerIndex = H3Index.FromLatLng(new LatLng(centerLatRad, centerLngRad), resolution);

var cluster = new List<H3Index> { centerIndex };
foreach (var ringCell in centerIndex.GridDiskDistances(1))
{
    if ((ulong)ringCell.Index != (ulong)centerIndex)
        cluster.Add(ringCell.Index);
}

Console.WriteLine($"-- Cluster size: {cluster.Count} cells");
Console.WriteLine($"INSERT INTO \"Claims\" (\"Id\", \"UserId\", \"CellCount\", \"AreaM2\", \"CreatedAt\", \"PolygonJson\") VALUES ('{claimId}', '{userId}', {cluster.Count}, {cluster.Count * 2150}, '{now}', '[]');");

foreach (var cell in cluster)
{
    var cellId = (long)(ulong)cell;
    var center = cell.ToLatLng();
    var lat = center.LatitudeDegrees;
    var lng = center.LongitudeDegrees;
    var parent = cell.GetParentForResolution(3);
    var parentId = (long)(ulong)parent;

    // Get real boundary
    var polygon = cell.GetCellBoundary(factory);
    var coords = polygon.ExteriorRing.Coordinates;
    var boundary = new double[coords.Length][];
    for (int i = 0; i < coords.Length; i++)
        boundary[i] = new[] { coords[i].Y, coords[i].X };
    var boundaryJson = JsonSerializer.Serialize(boundary);

    Console.WriteLine($"INSERT INTO \"TerritoryCells\" (\"CellId\", \"OwnerId\", \"ClaimId\", \"ClaimedAt\", \"CooldownExpiresAt\", \"CenterLat\", \"CenterLng\", \"ParentCellId\", \"BoundaryJson\") VALUES ({cellId}, '{userId}', '{claimId}', '{now}', '{cooldown}', {lat}, {lng}, {parentId}, '{boundaryJson.Replace("'", "''")}');");
}

// Update user hex count
Console.WriteLine($"UPDATE \"Users\" SET \"HexCount\" = \"HexCount\" + {cluster.Count} WHERE \"Id\" = '{userId}';");
