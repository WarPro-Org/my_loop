using System.Reflection;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Moq;
using MyLoop.Api.Controllers;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Models;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Coverage for LeaderboardController (issue #73 / #69B) — a Docker-free target the
/// existing *AuthTests classes don't reach because leaderboard endpoints carry no per-user
/// ownership check (they only require SOME authenticated caller). This mirrors that pattern:
/// a class-level [Authorize] regression guard, plus thin-controller pass-through behavior.
/// </summary>
public class LeaderboardControllerTests
{
    private static LeaderboardController Build(Mock<ILeaderboardService> leaderboard) =>
        new(leaderboard.Object);

    [Fact]
    public void Controller_requires_authorization()
    {
        // Leaderboard entries surface a player's derived location (city/country scope) and
        // rank — the [Authorize] attribute is the only thing keeping this endpoint from being
        // callable anonymously. A silent removal of the attribute would only fail in the full
        // ASP.NET pipeline, never in a controller-level unit test that calls the action
        // directly, so this checks the attribute is still declared.
        var attribute = typeof(LeaderboardController).GetCustomAttribute<AuthorizeAttribute>();

        Assert.NotNull(attribute);
    }

    [Fact]
    public async Task GetLeaderboard_with_no_scope_defaults_to_city()
    {
        var leaderboard = new Mock<ILeaderboardService>();
        leaderboard.Setup(l => l.GetLeaderboard(It.IsAny<double>(), It.IsAny<double>(), It.IsAny<Guid?>(), "city"))
            .ReturnsAsync(new LeaderboardResponse { Scope = "city" });

        var result = await Build(leaderboard).GetLeaderboard(12.9, 77.5, null, scope: null);

        var ok = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<LeaderboardResponse>(ok.Value);
        Assert.Equal("city", response.Scope);
        leaderboard.Verify(l => l.GetLeaderboard(12.9, 77.5, null, "city"), Times.Once);
    }

    [Theory]
    [InlineData("country")]
    [InlineData("world")]
    public async Task GetLeaderboard_passes_an_explicit_scope_through_unchanged(string scope)
    {
        var leaderboard = new Mock<ILeaderboardService>();
        leaderboard.Setup(l => l.GetLeaderboard(It.IsAny<double>(), It.IsAny<double>(), It.IsAny<Guid?>(), scope))
            .ReturnsAsync(new LeaderboardResponse { Scope = scope });

        var result = await Build(leaderboard).GetLeaderboard(12.9, 77.5, null, scope);

        Assert.IsType<OkObjectResult>(result);
        leaderboard.Verify(l => l.GetLeaderboard(12.9, 77.5, null, scope), Times.Once);
        // Must NOT silently fall back to "city" for a caller-supplied scope.
        leaderboard.Verify(l => l.GetLeaderboard(It.IsAny<double>(), It.IsAny<double>(), It.IsAny<Guid?>(), "city"), Times.Never);
    }

    [Fact]
    public async Task GetLeaderboard_passes_the_userId_query_parameter_through_for_rank_lookup()
    {
        // userId is a client-supplied [FromQuery] value, not the authenticated caller's identity;
        // this only pins the pass-through, not any identity binding.
        var userId = Guid.NewGuid();
        var leaderboard = new Mock<ILeaderboardService>();
        leaderboard.Setup(l => l.GetLeaderboard(It.IsAny<double>(), It.IsAny<double>(), userId, It.IsAny<string>()))
            .ReturnsAsync(new LeaderboardResponse());

        await Build(leaderboard).GetLeaderboard(0, 0, userId, "city");

        leaderboard.Verify(l => l.GetLeaderboard(0, 0, userId, "city"), Times.Once);
    }

    [Fact]
    public void LeaderboardController_no_longer_exposes_a_client_triggered_refresh_endpoint()
    {
        // Issue #109: the removed POST /api/leaderboard/refresh action (an O(total cells)
        // recompute any authenticated user could fire up to 120 times/min) must not silently
        // come back — the refresh now runs only from LeaderboardRefreshWorker. Pure reflection,
        // so it lives here in the Docker-free class rather than a Testcontainers fixture.
        var actionMethods = typeof(LeaderboardController)
            .GetMethods()
            .Where(m => m.DeclaringType == typeof(LeaderboardController))
            .Select(m => m.Name)
            .ToList();

        Assert.DoesNotContain("Refresh", actionMethods);
        Assert.Equal(["GetLeaderboard"], actionMethods);
    }
}
