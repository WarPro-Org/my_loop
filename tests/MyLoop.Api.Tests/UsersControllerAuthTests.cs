using Microsoft.AspNetCore.Mvc;
using Moq;
using MyLoop.Api.Controllers;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Models;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// The destructive user endpoints (delete account, register device token) must reject
/// any caller who is not the targeted user. These are the highest-impact BOLA fixes:
/// account destruction and push-notification hijacking.
///
/// The deny path returns before any database/geocoding access, so those concrete
/// dependencies are intentionally null here.
/// </summary>
public class UsersControllerAuthTests
{
    private static UsersController Build(
        Mock<IUserService> users,
        Mock<IPushNotificationService> push,
        Mock<ICurrentUser> currentUser) =>
        new(users.Object, Mock.Of<IValidationService>(), push.Object,
            geocoding: null!, db: null!, currentUser.Object);

    [Fact]
    public async Task DeleteAccount_for_another_user_is_forbidden_and_deletes_nothing()
    {
        var callerId = Guid.NewGuid();
        var victimId = Guid.NewGuid();

        var users = new Mock<IUserService>();
        var push = new Mock<IPushNotificationService>();
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(callerId);

        var result = await Build(users, push, currentUser).DeleteAccount(victimId);

        Assert.IsType<ForbidResult>(result);
        users.Verify(u => u.DeleteAccount(It.IsAny<Guid>()), Times.Never);
    }

    [Fact]
    public async Task RegisterDeviceToken_for_another_user_is_forbidden_and_registers_nothing()
    {
        var callerId = Guid.NewGuid();
        var victimId = Guid.NewGuid();

        var users = new Mock<IUserService>();
        var push = new Mock<IPushNotificationService>();
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(callerId);

        var result = await Build(users, push, currentUser)
            .RegisterDeviceToken(victimId, new DeviceTokenRequest { Token = "attacker-device" });

        Assert.IsType<ForbidResult>(result);
        push.Verify(p => p.RegisterDeviceToken(It.IsAny<Guid>(), It.IsAny<string>(), It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task DeleteAccount_when_unauthenticated_returns_401()
    {
        var users = new Mock<IUserService>();
        var push = new Mock<IPushNotificationService>();
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync((Guid?)null);

        var result = await Build(users, push, currentUser).DeleteAccount(Guid.NewGuid());

        Assert.IsType<UnauthorizedResult>(result);
        users.Verify(u => u.DeleteAccount(It.IsAny<Guid>()), Times.Never);
    }
}
