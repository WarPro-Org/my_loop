using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using MyLoop.Api.Controllers;
using MyLoop.Modules.Rules;

namespace MyLoop.V01.Tests.FR1;

/// <summary>FR1: GET /api/rules returns the app's rules, or 304 when the app is already current.</summary>
public class RulesControllerTests
{
    private const int RulesVersion = 7;

    private static RulesController Controller(string? ifNoneMatch = null)
    {
        var rules = new GameRules
        {
            Version = RulesVersion,
            Loop = new LoopRules { ClosureDistanceMeters = 50, MinPoints = 20, SkipNeighbors = 10, MinAreaSquareMeters = 5000 },
        };
        var controller = new RulesController(new RuleSettings(Options.Create(rules)))
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
        if (ifNoneMatch is not null)
            controller.Request.Headers.IfNoneMatch = ifNoneMatch;
        return controller;
    }

    [Fact]
    public void First_request_returns_rules_and_version_as_etag()
    {
        var controller = Controller();

        var result = Assert.IsType<OkObjectResult>(controller.Get());

        var body = Assert.IsType<ClientRules>(result.Value);
        Assert.Equal(RulesVersion, body.Version);
        Assert.Equal(50, body.LoopClosureDistanceMeters);
        Assert.Equal($"\"{RulesVersion}\"", controller.Response.Headers.ETag.ToString());
    }

    [Fact]
    public void App_with_current_version_gets_not_modified()
    {
        var controller = Controller(ifNoneMatch: $"\"{RulesVersion}\"");

        var result = Assert.IsType<StatusCodeResult>(controller.Get());

        Assert.Equal(StatusCodes.Status304NotModified, result.StatusCode);
    }

    [Fact]
    public void App_with_older_version_gets_the_new_rules()
    {
        var controller = Controller(ifNoneMatch: $"\"{RulesVersion - 1}\"");

        Assert.IsType<OkObjectResult>(controller.Get());
    }
}
