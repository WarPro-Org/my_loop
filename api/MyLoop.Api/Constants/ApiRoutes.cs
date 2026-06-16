namespace MyLoop.Api.Constants;

/// <summary>
/// Centralized route paths and well-known query keys, so endpoint strings are defined once
/// instead of being duplicated as magic strings across the pipeline and controllers.
/// </summary>
public static class ApiRoutes
{
    public const string Health = "/";
    public const string Privacy = "/privacy";
    public const string Terms = "/terms";

    /// <summary>Prefix for all SignalR hub paths (rate-limit and request-logging rules key off it).</summary>
    public const string HubsPrefix = "/hubs";
    public const string TerritoryHub = "/hubs/territory";

    /// <summary>Query-string parameter SignalR uses to pass the JWT on the WebSocket upgrade.</summary>
    public const string AccessTokenQueryParam = "access_token";
}
