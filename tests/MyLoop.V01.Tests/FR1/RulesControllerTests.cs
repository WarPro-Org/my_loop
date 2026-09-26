using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using MyLoop.Api.Controllers;
using MyLoop.Modules.Rules;

namespace MyLoop.V01.Tests.FR1;

/// <summary>FR1: GET /api/rules returns the app's rules, or 304 when the app already has them.</summary>
public class RulesControllerTests
{
    private const int RulesVersion = 7;

    private static RuleSettings Settings(double closureDistanceMeters = 50) =>
        new(Options.Create(new GameRules
        {
            Version = RulesVersion,
            Loop = new LoopRules
            {
                ClosureDistanceMeters = closureDistanceMeters, MinPoints = 20, SkipNeighbors = 10, MinAreaSquareMeters = 5000,
            },
        }));

    private static RulesController Controller(IRuleSettings settings, string? ifNoneMatch = null)
    {
        var controller = new RulesController(settings)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
        if (ifNoneMatch is not null)
            controller.Request.Headers.IfNoneMatch = ifNoneMatch;
        return controller;
    }

    [Fact]
    public void First_request_returns_rules_and_their_fingerprint_as_etag()
    {
        var settings = Settings();
        var controller = Controller(settings);

        var result = Assert.IsType<OkObjectResult>(controller.Get());

        var body = Assert.IsType<ClientRules>(result.Value);
        Assert.Equal(RulesVersion, body.Version);
        Assert.Equal(50, body.LoopClosureDistanceMeters);
        Assert.Equal($"\"{settings.ClientRulesTag}\"", controller.Response.Headers.ETag.ToString());
    }

    [Fact]
    public void App_with_current_rules_gets_not_modified()
    {
        var settings = Settings();

        var result = Assert.IsType<StatusCodeResult>(Controller(settings, $"\"{settings.ClientRulesTag}\"").Get());

        Assert.Equal(StatusCodes.Status304NotModified, result.StatusCode);
    }

    [Fact]
    public void App_with_older_rules_gets_the_new_rules()
    {
        Assert.IsType<OkObjectResult>(Controller(Settings(), "\"6-0000000000000000\"").Get());
    }

    [Fact]
    public void Changed_value_without_a_version_bump_still_reaches_the_app()
    {
        // Someone edits a value (or overrides it in production) but forgets to bump Version.
        var before = Settings(closureDistanceMeters: 50);
        var after = Settings(closureDistanceMeters: 40);

        Assert.NotEqual(before.ClientRulesTag, after.ClientRulesTag);
        Assert.IsType<OkObjectResult>(Controller(after, $"\"{before.ClientRulesTag}\"").Get());
    }
}
