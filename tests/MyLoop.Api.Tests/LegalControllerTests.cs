using System.Reflection;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc;
using Moq;
using MyLoop.Api.Controllers;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Coverage for LegalController (issue #73 / #69B), which serves the Apple-required Privacy
/// Policy and Terms pages (App Store Guideline 5.1.1) from static files. Docker-free: uses a
/// real temp directory standing in for wwwroot, since the controller reads files directly
/// rather than through an injectable abstraction.
/// </summary>
public class LegalControllerTests : IDisposable
{
    private readonly string _webRoot =
        Path.Combine(Path.GetTempPath(), "myloop-legal-tests-" + Guid.NewGuid());

    public void Dispose()
    {
        if (Directory.Exists(_webRoot))
            Directory.Delete(_webRoot, recursive: true);
    }

    private LegalController Build()
    {
        var environment = new Mock<IWebHostEnvironment>();
        environment.Setup(e => e.WebRootPath).Returns(_webRoot);
        return new LegalController(environment.Object);
    }

    private void SeedLegalFile(string fileName, string html)
    {
        var legalDir = Path.Combine(_webRoot, "legal");
        Directory.CreateDirectory(legalDir);
        File.WriteAllText(Path.Combine(legalDir, fileName), html);
    }

    [Fact]
    public void Controller_allows_anonymous_access()
    {
        // Must stay reachable pre-auth: it's linked from the App Store listing and shown
        // before sign-in, per Apple Guideline 5.1.1 (see the controller's own summary).
        var attribute = typeof(LegalController).GetCustomAttribute<AllowAnonymousAttribute>();

        Assert.NotNull(attribute);
    }

    [Fact]
    public void Privacy_returns_the_html_file_content_when_present()
    {
        SeedLegalFile("privacy.html", "<html>privacy</html>");

        var result = Build().Privacy();

        var content = Assert.IsType<ContentResult>(result);
        Assert.Equal("<html>privacy</html>", content.Content);
        Assert.Equal("text/html", content.ContentType);
    }

    [Fact]
    public void Terms_returns_the_html_file_content_when_present()
    {
        SeedLegalFile("terms.html", "<html>terms</html>");

        var result = Build().Terms();

        var content = Assert.IsType<ContentResult>(result);
        Assert.Equal("<html>terms</html>", content.Content);
        Assert.Equal("text/html", content.ContentType);
    }

    [Fact]
    public void Privacy_returns_404_when_the_file_is_missing()
    {
        // _webRoot exists but nothing was seeded into it.
        Directory.CreateDirectory(_webRoot);

        var result = Build().Privacy();

        Assert.IsType<NotFoundResult>(result);
    }

    [Fact]
    public void Terms_returns_404_when_the_web_root_itself_does_not_exist()
    {
        // No SeedLegalFile call — _webRoot is never created on disk at all.
        var result = Build().Terms();

        Assert.IsType<NotFoundResult>(result);
    }
}
