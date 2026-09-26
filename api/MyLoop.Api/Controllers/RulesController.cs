using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;
using MyLoop.Api.Constants;
using MyLoop.Modules.Rules;

namespace MyLoop.Api.Controllers;

/// <summary>
/// Hands the app the rules it needs (FR1). The rules version is the ETag, so an app that already
/// has the current version gets 304 Not Modified and keeps its saved copy.
/// </summary>
[ApiController]
[Route(ApiRoutes.Rules)]
[Authorize]
public class RulesController : ControllerBase
{
    private readonly IRuleSettings _rules;

    public RulesController(IRuleSettings rules)
    {
        _rules = rules;
    }

    [HttpGet]
    public IActionResult Get()
    {
        var clientRules = _rules.GetClientRules();
        var etag = new EntityTagHeaderValue($"\"{clientRules.Version}\"");

        Response.GetTypedHeaders().ETag = etag;
        var ifNoneMatch = Request.GetTypedHeaders().IfNoneMatch;
        if (ifNoneMatch.Any(tag => tag.Compare(etag, useStrongComparison: false)))
            return StatusCode(StatusCodes.Status304NotModified);

        return Ok(clientRules);
    }
}
