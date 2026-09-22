using System.Reflection;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Controllers;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Coverage for HealthController (issue #73 / #69B) — the liveness probe load balancers and
/// uptime checks hit. The single real risk here is auth: if [AllowAnonymous] were ever removed
/// or replaced with an implicit [Authorize], every health check would start failing with 401s,
/// which looks like a total outage to infrastructure tooling even though the API is fine.
/// </summary>
public class HealthControllerTests
{
    [Fact]
    public void Get_action_allows_anonymous_access()
    {
        var method = typeof(HealthController).GetMethod(nameof(HealthController.Get));

        var attribute = method!.GetCustomAttribute<AllowAnonymousAttribute>();

        Assert.NotNull(attribute);
    }

    [Fact]
    public void Get_returns_the_running_message()
    {
        var result = new HealthController().Get();

        var content = Assert.IsType<ContentResult>(result);
        Assert.Equal("MyLoop API is running", content.Content);
    }
}
