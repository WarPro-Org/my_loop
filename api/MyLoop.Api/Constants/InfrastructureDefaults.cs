namespace MyLoop.Api.Constants;

/// <summary>
/// Infrastructure/runtime defaults (rate limiting, logging sinks, external timeouts, auth).
/// Kept separate from <see cref="GameConstants"/>, which is gameplay-only. Environment-specific
/// values (e.g. the Firebase project id) are overridable via configuration where noted.
/// </summary>
public static class InfrastructureDefaults
{
    // --- Rate limiting (per authenticated user, falling back to client IP) ---
    public const int RateLimitPermitLimit = 120;
    public const int RateLimitWindowSeconds = 60;
    public const int RateLimitQueueLimit = 0;

    // --- External geocoding (Nominatim is best-effort) ---
    public const int GeocodingTimeoutSeconds = 5;

    // --- Serilog rolling-file sink ---
    public const string LogDirectoryName = "logs";
    public const string LogFileNamePattern = "myloop-.log";
    public const int LogRetainedFileCountLimit = 7;
    public const long LogFileSizeLimitBytes = 50_000_000;

    // --- Mock walk simulation (#29) ---
    /// <summary>
    /// Header whose presence marks a request as originating from the in-app mock walk simulator.
    /// The Flutter client attaches it only in debug builds while a simulated walk is running. It is
    /// read in exactly one place — <c>MockLogContextMiddleware</c> — and branches logging only; no
    /// game logic, validation, or persistence inspects it, so a mock walk hits the identical server
    /// path (anti-cheat included) as a real one.
    /// </summary>
    public const string MockRequestHeader = "X-MyLoop-Mock";
    /// <summary>LogContext property set on mock requests so their events route to <see cref="MockLogDirectoryName"/>.</summary>
    public const string MockLogContextProperty = "IsMock";
    /// <summary>Directory (under the same root as <see cref="LogDirectoryName"/>) for segregated mock logs.</summary>
    public const string MockLogDirectoryName = "MockLogs";
    public const string MockLogFileNamePattern = "mock-.log";

    // --- CORS ---
    /// <summary>Fallback origin when no browser origins are configured (the native client is CORS-exempt).</summary>
    public const string DefaultCorsOrigin = "http://localhost";

    // --- Firebase authentication ---
    /// <summary>Config key for the Firebase project id; overrides <see cref="DefaultFirebaseProjectId"/>.</summary>
    public const string FirebaseProjectIdConfigKey = "Authentication:Firebase:ProjectId";
    public const string DefaultFirebaseProjectId = "myloop-6aefc";
    /// <summary>Authority/issuer template; the audience is the project id itself.</summary>
    public const string FirebaseAuthorityFormat = "https://securetoken.google.com/{0}";
}
