using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Constants;

namespace MyLoop.Api.Controllers;

/// <summary>
/// Serves the Apple-required Privacy Policy and Terms pages (App Store Guideline 5.1.1) as static
/// HTML from <c>wwwroot/legal</c>. Anonymous and HTML so they're linkable from the store listing
/// and the app.
/// </summary>
[ApiController]
[AllowAnonymous]
public class LegalController : ControllerBase
{
    private const string LegalDirectory = "legal";
    private readonly IWebHostEnvironment _environment;

    public LegalController(IWebHostEnvironment environment) => _environment = environment;

    [HttpGet(ApiRoutes.Privacy)]
    public IActionResult Privacy() => HtmlPage("privacy.html");

    [HttpGet(ApiRoutes.Terms)]
    public IActionResult Terms() => HtmlPage("terms.html");

    private IActionResult HtmlPage(string fileName)
    {
        var webRoot = _environment.WebRootPath ?? Path.Combine(_environment.ContentRootPath, "wwwroot");
        // Guard against a rooted/traversal segment silently discarding the web-root prefix; callers
        // only ever pass a bare file name, so reduce to that defensively.
        var path = Path.Combine(webRoot, LegalDirectory, Path.GetFileName(fileName));
        if (!System.IO.File.Exists(path))
            return NotFound();
        return Content(System.IO.File.ReadAllText(path), "text/html");
    }
}
