using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using MyLoop.Api.Constants;
using MyLoop.Api.Controllers;
using MyLoop.Modules.Rules;

namespace MyLoop.V01.Tests.FR1;

/// <summary>
/// FR1: GET /api/rules over real HTTP — routing, sign-in, MVC's JSON output and the ETag header —
/// returns exactly the shared sample the phone's tests read (tests/contracts/client_rules.json).
/// The host is set up like Program.cs (AddMyLoopRules + AddControllers with default JSON); only
/// the Firebase sign-in is swapped for a test scheme, and the database and other modules are left out.
/// </summary>
public sealed class RulesHttpTests : IAsyncLifetime
{
    private const string TestScheme = "Test";
    private WebApplication _app = null!;
    private HttpClient _client = null!;

    public async Task InitializeAsync()
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        builder.Services.AddMyLoopRules(SampleRulesConfiguration());
        builder.Services.AddControllers().AddApplicationPart(typeof(RulesController).Assembly);
        builder.Services.AddAuthentication(TestScheme)
            .AddScheme<AuthenticationSchemeOptions, SignedInHandler>(TestScheme, _ => { });
        builder.Services.AddAuthorization();

        _app = builder.Build();
        _app.UseAuthentication();
        _app.UseAuthorization();
        _app.MapControllers();
        await _app.StartAsync();

        var address = _app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.First();
        _client = new HttpClient { BaseAddress = new Uri(address) };
    }

    public async Task DisposeAsync()
    {
        _client.Dispose();
        await _app.DisposeAsync();
    }

    /// <summary>The shipped rules with the sample's values for every field the app sees.</summary>
    private static IConfiguration SampleRulesConfiguration()
    {
        var sample = new Dictionary<string, string?>
        {
            ["GameRules:Version"] = "3",
            ["GameRules:Loop:ClosureDistanceMeters"] = "42.5",
            ["GameRules:Loop:MinPoints"] = "21",
            ["GameRules:Loop:SkipNeighbors"] = "7",
            ["GameRules:Gps:AccuracyThresholdMeters"] = "33.5",
        };
        return new ConfigurationBuilder()
            .SetBasePath(AppContext.BaseDirectory)
            .AddJsonFile("shipped-appsettings.json")
            .AddInMemoryCollection(sample)
            .Build();
    }

    [Fact]
    public async Task Rules_reply_over_http_is_exactly_the_shared_sample()
    {
        var sample = JsonNode.Parse(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "contracts", "client_rules.json")));

        using var response = await _client.GetAsync($"/{ApiRoutes.Rules}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);
        var sent = JsonNode.Parse(await response.Content.ReadAsStringAsync());
        Assert.True(JsonNode.DeepEquals(sample, sent), $"sent {sent?.ToJsonString()}, sample {sample?.ToJsonString()}");
    }

    [Fact]
    public async Task Rules_etag_sent_back_over_http_gives_not_modified()
    {
        using var first = await _client.GetAsync($"/{ApiRoutes.Rules}");
        var etag = first.Headers.ETag;
        Assert.NotNull(etag);

        using var request = new HttpRequestMessage(HttpMethod.Get, $"/{ApiRoutes.Rules}");
        request.Headers.IfNoneMatch.Add(etag);
        using var second = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.NotModified, second.StatusCode);
        Assert.Empty(await second.Content.ReadAsStringAsync());
    }

    /// <summary>Signs every request in, standing in for the Firebase JWT check.</summary>
    private sealed class SignedInHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
        : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
    {
        protected override Task<AuthenticateResult> HandleAuthenticateAsync()
        {
            var identity = new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, "test-user")], TestScheme);
            return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), TestScheme)));
        }
    }
}
