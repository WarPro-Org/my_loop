namespace MyLoop.Api.Constants;

/// <summary>
/// Claim names on the validated Firebase JWT. Firebase puts the uid in <c>user_id</c>; <c>sub</c>
/// carries the same value. Centralized so these strings are defined once across auth, the rate
/// limiter, request-log enrichment, and the SignalR hub.
/// </summary>
public static class FirebaseClaims
{
    public const string UserId = "user_id";
    public const string Subject = "sub";

    /// <summary>Property name used to enrich request logs with the caller's uid.</summary>
    public const string EnrichedUidProperty = "FirebaseUid";
}
