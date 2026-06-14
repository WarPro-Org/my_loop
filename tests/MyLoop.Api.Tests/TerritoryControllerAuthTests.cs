using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using MyLoop.Api.Controllers;
using MyLoop.Api.Interfaces;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Private territory endpoints (stolen cells, walk history, exploration) must only
/// be readable by their owner.
/// </summary>
public class TerritoryControllerAuthTests
{
    private static TerritoryController Build(
        Mock<ITerritoryService> territory, Mock<ICurrentUser> currentUser) =>
        new(territory.Object, currentUser.Object, NullLogger<TerritoryController>.Instance);

    [Fact]
    public async Task GetStolenCells_for_another_user_is_forbidden_and_reads_nothing()
    {
        var callerId = Guid.NewGuid();
        var victimId = Guid.NewGuid();

        var territory = new Mock<ITerritoryService>();
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(callerId);

        var result = await Build(territory, currentUser).GetStolenCells(victimId, 7);

        Assert.IsType<ForbidResult>(result);
        territory.Verify(t => t.GetStolenCells(It.IsAny<Guid>(), It.IsAny<int>()), Times.Never);
    }

    [Fact]
    public async Task GetClaimHistory_for_another_user_is_forbidden()
    {
        var callerId = Guid.NewGuid();
        var otherId = Guid.NewGuid();

        var territory = new Mock<ITerritoryService>();
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(callerId);

        var result = await Build(territory, currentUser).GetClaimHistory(otherId);

        Assert.IsType<ForbidResult>(result);
        territory.Verify(t => t.GetClaimHistory(It.IsAny<Guid>()), Times.Never);
    }

    [Fact]
    public async Task GetExplorationStats_when_unauthenticated_returns_401()
    {
        var territory = new Mock<ITerritoryService>();
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync((Guid?)null);

        var result = await Build(territory, currentUser).GetExplorationStats(Guid.NewGuid(), 0, 0);

        Assert.IsType<UnauthorizedResult>(result);
        territory.Verify(t => t.GetExplorationStats(It.IsAny<Guid>(), It.IsAny<double>(), It.IsAny<double>()), Times.Never);
    }
}
