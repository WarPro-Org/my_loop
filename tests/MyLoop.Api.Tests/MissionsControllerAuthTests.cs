using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Moq;
using MyLoop.Api.Controllers;
using MyLoop.Api.Data;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Daily-mission / XP endpoints expose per-user progress and must only be readable
/// by their owner. Before the fix MissionsController had no [Authorize] and trusted
/// the route id, so any caller could enumerate any user's missions and XP by GUID.
/// </summary>
public class MissionsControllerAuthTests
{
    // DenySelf short-circuits before any DB access, so a provider-less context is safe.
    private static AppDbContext NoDb() =>
        new(new DbContextOptionsBuilder<AppDbContext>().Options);

    private static MissionsController Build(Mock<IMissionService> missions, Mock<ICurrentUser> currentUser) =>
        new(missions.Object, NoDb(), currentUser.Object);

    [Fact]
    public async Task GetMissions_for_another_user_is_forbidden_and_reads_nothing()
    {
        var callerId = Guid.NewGuid();
        var otherId = Guid.NewGuid();

        var missions = new Mock<IMissionService>();
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(callerId);

        var result = await Build(missions, currentUser).GetMissions(otherId);

        Assert.IsType<ForbidResult>(result);
        missions.Verify(m => m.GetTodaysMissions(It.IsAny<Guid>()), Times.Never);
    }

    [Fact]
    public async Task GetXpInfo_for_another_user_is_forbidden()
    {
        var callerId = Guid.NewGuid();
        var otherId = Guid.NewGuid();

        var missions = new Mock<IMissionService>();
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(callerId);

        var result = await Build(missions, currentUser).GetXpInfo(otherId);

        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task GetMissions_when_unauthenticated_returns_401()
    {
        var missions = new Mock<IMissionService>();
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync((Guid?)null);

        var result = await Build(missions, currentUser).GetMissions(Guid.NewGuid());

        Assert.IsType<UnauthorizedResult>(result);
        missions.Verify(m => m.GetTodaysMissions(It.IsAny<Guid>()), Times.Never);
    }
}
