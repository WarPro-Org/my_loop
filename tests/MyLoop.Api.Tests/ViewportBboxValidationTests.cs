using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using MyLoop.Api.Controllers;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Models;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Invalid viewport bboxes (#114 review BLOCKER). The ASP.NET double binder accepts NaN,
/// ±Infinity and huge finite values. Before the fix, NaN defeated the "too wide" span guard
/// and <c>Math.Min(lat + step, maxLat)</c> stayed NaN, and at 1e16 <c>lat + 0.4 == lat</c> —
/// either way the perimeter loop never ended and one request pinned a thread at 100% CPU.
/// </summary>
public static class ViewportBboxCases
{
    private const double Huge = 1e16;

    /// <summary>minLat, minLng, maxLat, maxLng — every one must be rejected.</summary>
    public static TheoryData<double, double, double, double> Invalid => new()
    {
        // NaN in each position (hung pre-fix).
        { double.NaN, 77.5, 13.0, 77.6 },
        { 12.9, double.NaN, 13.0, 77.6 },
        { 12.9, 77.5, double.NaN, 77.6 },
        { 12.9, 77.5, 13.0, double.NaN },
        // ±Infinity.
        { double.PositiveInfinity, 77.5, 13.0, 77.6 },
        { 12.9, 77.5, double.PositiveInfinity, 77.6 },
        { double.NegativeInfinity, 77.5, 13.0, 77.6 },
        { 12.9, double.NegativeInfinity, 13.0, 77.6 },
        { 12.9, 77.5, 13.0, double.PositiveInfinity },
        // Huge finite values: a 2° span passes the span guard, but lat + step == lat (hung pre-fix).
        { Huge, 77.5, Huge + 2, 77.6 },
        { 12.9, Huge, 13.0, Huge + 2 },
        // Inverted bounds.
        { 13.0, 77.5, 12.9, 77.6 },
        { 12.9, 77.6, 13.0, 77.5 },
        // Out of WGS84 range.
        { 90.5, 77.5, 91.0, 77.6 },
        { -91.0, 77.5, -90.5, 77.6 },
        { 12.9, 180.5, 13.0, 181.0 },
        { 12.9, -181.0, 13.0, -180.5 },
    };
}

public class HexGridBboxValidationTests
{
    // Generous for a ≤ ~100-sample computation, tiny next to "never returns".
    private static readonly TimeSpan CompletionBound = TimeSpan.FromSeconds(5);

    private static HexGridService Service() => new(new GeoService(), TestRules.Settings);

    /// <summary>
    /// Runs the call on the thread pool and fails if it has not returned within the bound —
    /// a hung call must fail the test, not hang the suite. Returns the thrown exception, if any.
    /// </summary>
    private static async Task<Exception?> RunBounded(Action call)
    {
        var task = Task.Run(call);
        var finished = await Task.WhenAny(task, Task.Delay(CompletionBound));
        Assert.True(finished == task, $"GetRegionIdsForBbox did not return within {CompletionBound}");
        return task.Exception?.InnerException;
    }

    [Theory]
    [MemberData(nameof(ViewportBboxCases.Invalid), MemberType = typeof(ViewportBboxCases))]
    public async Task Invalid_bbox_throws_promptly_instead_of_looping(
        double minLat, double minLng, double maxLat, double maxLng)
    {
        var thrown = await RunBounded(() => Service().GetRegionIdsForBbox(minLat, minLng, maxLat, maxLng));

        Assert.IsType<ArgumentException>(thrown);
    }

    [Theory]
    // A single point and a zero-height / zero-width line: no interior, so H3's polyfill is
    // skipped (it throws on a collapsed ring); the center/perimeter seeds must still cover it.
    [InlineData(12.9716, 77.5946, 12.9716, 77.5946)]
    [InlineData(12.9716, 77.0, 12.9716, 78.0)]
    [InlineData(12.0, 77.5946, 13.0, 77.5946)]
    // Bbox touching the pole and the antimeridian: valid, must terminate.
    [InlineData(85.0, 175.0, 90.0, 180.0)]
    public async Task Degenerate_and_edge_of_world_bboxes_cover_their_corner_parent(
        double minLat, double minLng, double maxLat, double maxLng)
    {
        var svc = Service();
        IReadOnlyCollection<long> regions = [];

        var thrown = await RunBounded(() => regions = svc.GetRegionIdsForBbox(minLat, minLng, maxLat, maxLng));

        Assert.Null(thrown);
        Assert.Contains(svc.GetParentCellId(svc.GetCellAtPoint(minLat, minLng).CellId), regions);
        Assert.Contains(svc.GetParentCellId(svc.GetCellAtPoint(maxLat, maxLng).CellId), regions);
    }
}

public class TerritoryControllerViewportValidationTests
{
    private static TerritoryController Build(Mock<ITerritoryService> territory) =>
        new(territory.Object, Mock.Of<ICurrentUser>(), NullLogger<TerritoryController>.Instance)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };

    [Theory]
    [MemberData(nameof(ViewportBboxCases.Invalid), MemberType = typeof(ViewportBboxCases))]
    public async Task Invalid_bbox_returns_400_and_never_reaches_the_service(
        double minLat, double minLng, double maxLat, double maxLng)
    {
        var territory = new Mock<ITerritoryService>();

        var result = await Build(territory).GetTerritoriesInViewport(minLat, minLng, maxLat, maxLng);

        Assert.IsType<BadRequestObjectResult>(result);
        territory.Verify(t => t.GetTerritoriesInViewport(
            It.IsAny<double>(), It.IsAny<double>(), It.IsAny<double>(), It.IsAny<double>()), Times.Never);
    }

    [Theory]
    [InlineData(12.9, 77.5, 13.0, 77.6)]
    // The inclusive WGS84 limits and a zero-area bbox are valid.
    [InlineData(-90.0, -180.0, 90.0, 180.0)]
    [InlineData(12.9, 77.5, 12.9, 77.5)]
    public async Task Valid_bbox_is_served_with_the_truncation_header(
        double minLat, double minLng, double maxLat, double maxLng)
    {
        var territory = new Mock<ITerritoryService>();
        territory.Setup(t => t.GetTerritoriesInViewport(minLat, minLng, maxLat, maxLng))
            .ReturnsAsync(new TerritoryViewportResult { Cells = [], Truncated = false });
        var controller = Build(territory);

        var result = await controller.GetTerritoriesInViewport(minLat, minLng, maxLat, maxLng);

        Assert.IsType<OkObjectResult>(result);
        Assert.Equal("false", controller.Response.Headers["X-Viewport-Truncated"].ToString());
    }
}
