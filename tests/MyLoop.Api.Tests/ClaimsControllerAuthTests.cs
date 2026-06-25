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

    // Wires a REAL PathValidationService so the batch-step anti-cheat gates actually run
    // (the default Mock returns null for every check, i.e. "always valid").
    private static ClaimsController BuildWithRealValidator(
        Mock<ITerritoryService> territory, Mock<ICurrentUser> currentUser) =>
        new(territory.Object, Mock.Of<IHexGridService>(), currentUser.Object,
            new PathValidationService(NullLogger<PathValidationService>.Instance),
            NullLogger<ClaimsController>.Instance);

    private static BatchStepClaimRequest StraightNorthBatch(int count)
    {
        var t0 = new DateTime(2026, 6, 11, 9, 0, 0, DateTimeKind.Utc);
        var request = new BatchStepClaimRequest { LocalDate = "2026-06-11" };
        // ~11m north every 5s ≈ 2.2 m/s (passes the speed gate) but dead-straight,
        // so bearing-stddev is 0 — only the smoothness gate can catch it.
        for (var i = 0; i < count; i++)
            request.Points.Add(new BatchStepPoint
            {
                ClientId = $"c{i}",
                Lat = 12.9000 + i * 0.0001,
                Lng = 77.5000,
                CapturedAt = t0.AddSeconds(i * 5),
            });
        return request;
    }

    // Northward track with irregular per-hop jitter (deterministic): bearing-change
    // stdDev ≈ 17.8° clears the smoothness floor, and ~2.5 m/s clears the speed gate.
    private static readonly (double Lat, double Lng)[] NaturalWalk =
    [
        (12.900000, 77.500000), (12.900111, 77.499905), (12.900193, 77.499850),
        (12.900312, 77.499885), (12.900443, 77.499802), (12.900537, 77.499708),
        (12.900615, 77.499709), (12.900677, 77.499649), (12.900789, 77.499658),
        (12.900866, 77.499676), (12.900991, 77.499577), (12.901116, 77.499617),
        (12.901203, 77.499548), (12.901339, 77.499515),
    ];

    private static BatchStepClaimRequest JitteredBatch()
    {
        var t0 = new DateTime(2026, 6, 11, 9, 0, 0, DateTimeKind.Utc);
        var request = new BatchStepClaimRequest { LocalDate = "2026-06-11" };
        for (var i = 0; i < NaturalWalk.Length; i++)
            request.Points.Add(new BatchStepPoint
            {
                ClientId = $"c{i}",
                Lat = NaturalWalk[i].Lat,
                Lng = NaturalWalk[i].Lng,
                CapturedAt = t0.AddSeconds(i * 5),
            });
        return request;
    }

    [Fact]
    public async Task ClaimBatchStep_rejects_synthetic_straight_path_and_never_writes()
    {
        var callerId = Guid.NewGuid();
        var territory = new Mock<ITerritoryService>();
        territory.Setup(t => t.ProcessBatchStepClaim(
                It.IsAny<Guid>(), It.IsAny<string?>(), It.IsAny<List<BatchStepPoint>>()))
            .ReturnsAsync(new BatchStepClaimResponse());

        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(callerId);

        var controller = BuildWithRealValidator(territory, currentUser);

        var result = await controller.ClaimBatchStep(StraightNorthBatch(12));

        // Pre-#52 the batch-step path ran no smoothness gate, so this dead-straight synthetic
        // path would have reached ProcessBatchStepClaim and returned Ok. The gate must block it.
        Assert.IsType<BadRequestObjectResult>(result);
        territory.Verify(t => t.ProcessBatchStepClaim(
            It.IsAny<Guid>(), It.IsAny<string?>(), It.IsAny<List<BatchStepPoint>>()), Times.Never);
    }

    [Fact]
    public async Task ClaimBatchStep_allows_natural_jittered_path()
    {
        var callerId = Guid.NewGuid();
        var territory = new Mock<ITerritoryService>();
        territory.Setup(t => t.ProcessBatchStepClaim(
                It.IsAny<Guid>(), It.IsAny<string?>(), It.IsAny<List<BatchStepPoint>>()))
            .ReturnsAsync(new BatchStepClaimResponse());

        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(callerId);

        var controller = BuildWithRealValidator(territory, currentUser);

        var result = await controller.ClaimBatchStep(JitteredBatch());

        // Natural jitter clears both gates: the claim is processed.
        Assert.IsType<OkObjectResult>(result);
        territory.Verify(t => t.ProcessBatchStepClaim(
            callerId, It.IsAny<string?>(), It.IsAny<List<BatchStepPoint>>()), Times.Once);
    }

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
