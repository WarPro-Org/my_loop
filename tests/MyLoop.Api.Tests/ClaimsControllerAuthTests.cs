using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using MyLoop.Api.Controllers;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Models;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Proves claims are always attributed to the authenticated caller, never to a
/// UserId supplied in the request body (the core fix for the BOLA vulnerability).
/// </summary>
public class ClaimsControllerAuthTests
{
    private static double[][] ValidPath() =>
    [
        [12.9000, 77.5000],
        [12.9010, 77.5000],
        [12.9010, 77.5010],
        [12.9000, 77.5010],
    ];

    private static ClaimsController Build(
        Mock<ITerritoryService> territory, Mock<ICurrentUser> currentUser) =>
        new(territory.Object, Mock.Of<IHexGridService>(), currentUser.Object,
            Mock.Of<IPathValidationService>(), NullLogger<ClaimsController>.Instance);

    [Fact]
    public async Task SubmitClaim_uses_authenticated_caller_and_ignores_body_userId()
    {
        var callerId = Guid.NewGuid();
        var spoofedBodyUserId = Guid.NewGuid();

        var territory = new Mock<ITerritoryService>();
        territory.Setup(t => t.ProcessClaim(It.IsAny<Guid>(), It.IsAny<double[][]>()))
                 .ReturnsAsync(ClaimResult.Failure("short-circuit after identity check"));

        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(callerId);

        var controller = Build(territory, currentUser);
        var request = new ClaimRequest { UserId = spoofedBodyUserId, Path = ValidPath() };

        await controller.SubmitClaim(request);

        territory.Verify(t => t.ProcessClaim(callerId, It.IsAny<double[][]>()), Times.Once);
        territory.Verify(t => t.ProcessClaim(spoofedBodyUserId, It.IsAny<double[][]>()), Times.Never);
    }

    [Fact]
    public async Task SubmitClaim_returns_401_when_unauthenticated_and_never_writes()
    {
        var territory = new Mock<ITerritoryService>();
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync((Guid?)null);

        var controller = Build(territory, currentUser);
        var request = new ClaimRequest { UserId = Guid.NewGuid(), Path = ValidPath() };

        var result = await controller.SubmitClaim(request);

        Assert.IsType<UnauthorizedResult>(result);
        territory.Verify(t => t.ProcessClaim(It.IsAny<Guid>(), It.IsAny<double[][]>()), Times.Never);
    }
}
