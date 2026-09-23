using Firebase = FirebaseAdmin;
using Google.Apis.Auth.OAuth2;
using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Constants;
using MyLoop.Api.Data;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Services;

namespace MyLoop.Api.Configuration;

/// <summary>
/// Application service registrations, grouped by concern (SRP). Each method returns the service
/// collection for fluent chaining from Program.cs.
/// </summary>
public static class ServiceRegistrationExtensions
{
    public static IServiceCollection AddMyLoopDatabase(this IServiceCollection services, IConfiguration configuration) =>
        services.AddDbContext<AppDbContext>(options =>
            options.UseNpgsql(
                configuration.GetConnectionString("DefaultConnection"),
                // Neon scales to zero when idle; the first query after a cold start (or a pooled
                // connection dropped during suspension) surfaces as a transient failure. Retry it
                // transparently. NOTE: this installs a retrying execution strategy, so every
                // user-initiated transaction MUST run inside Database.CreateExecutionStrategy().
                npgsql => npgsql.EnableRetryOnFailure(
                    maxRetryCount: InfrastructureDefaults.DbMaxRetryCount,
                    maxRetryDelay: TimeSpan.FromSeconds(InfrastructureDefaults.DbMaxRetryDelaySeconds),
                    errorCodesToAdd: null)));

    /// <summary>Registers domain services, identity resolution, the geocoding client, and the decay,
    /// HexCount reconciliation, and leaderboard refresh background workers.</summary>
    public static IServiceCollection AddMyLoopServices(this IServiceCollection services)
    {
        services.AddScoped<IValidationService, ValidationService>();
        services.AddScoped<IGeoService, GeoService>();
        services.AddScoped<IHexGridService, HexGridService>();
        services.AddScoped<ITerritoryService, TerritoryService>();
        services.AddScoped<IUserService, UserService>();
        services.AddScoped<ILeaderboardService, LeaderboardService>();
        services.AddScoped<ITerritoryNotifier, TerritoryNotifier>();
        services.AddScoped<IPathValidationService, PathValidationService>();
        services.AddScoped<IPushNotificationService, PushNotificationService>();
        services.AddScoped<IMissionService, MissionService>();
        services.AddScoped<IAchievementService, AchievementService>();

        // A GENUINE singleton, so the service's throttle and in-memory caches are shared across
        // every caller. This used to be an AddSingleton followed by AddHttpClient<GeocodingService>,
        // and the typed-client registration silently overrode it — last registration wins — leaving
        // the service transient with per-instance throttle state that enforced nothing (#139 D2).
        //
        // Deliberately NOT a typed client: AddHttpClient<TClient> registers TClient as transient,
        // which is the whole bug. Building the HttpClient here keeps the singleton, and
        // PooledConnectionLifetime recovers the one thing IHttpClientFactory would have given us —
        // a long-lived HttpClient otherwise pins DNS for the life of the process.
        //
        // The timeout bounds external geocoding latency: Nominatim is best-effort and the service
        // falls back gracefully, so cap well below the 100s HttpClient default rather than tying up
        // request threads when the upstream is slow or unreachable.
        services.AddSingleton<GeocodingService>(sp => new GeocodingService(
            new HttpClient(new SocketsHttpHandler
            {
                PooledConnectionLifetime = TimeSpan.FromMinutes(
                    InfrastructureDefaults.GeocodingConnectionLifetimeMinutes),
            })
            {
                Timeout = TimeSpan.FromSeconds(InfrastructureDefaults.GeocodingTimeoutSeconds),
            },
            sp.GetRequiredService<ILogger<GeocodingService>>()));
        services.AddHostedService<DecayCleanupService>();
        // Backstop that repairs any HexCount drift back to the true owned-cell count.
        services.AddHostedService<HexCountReconciliationService>();
        // Recomputes the leaderboard snapshot on a timer instead of a client-triggered endpoint.
        services.AddHostedService<LeaderboardRefreshWorker>();

        services.AddHttpContextAccessor();
        services.AddMemoryCache();
        services.AddScoped<ICurrentUser, CurrentUser>();
        return services;
    }

    /// <summary>
    /// Registers the FCM sender used by <see cref="PushNotificationService"/>. Real Firebase
    /// delivery (<see cref="FirebaseFcmSender"/>) is wired up only when <c>Push:Enabled</c> is
    /// true and a service-account credential path is configured; otherwise
    /// <see cref="LoggingFcmSender"/> is registered so the app runs (and CI/local dev build and
    /// test) without live Firebase credentials.
    /// </summary>
    public static IServiceCollection AddMyLoopPushNotifications(this IServiceCollection services, IConfiguration configuration)
    {
        var enabled = configuration.GetValue<bool>(InfrastructureDefaults.PushEnabledConfigKey);
        var serviceAccountPath = configuration[InfrastructureDefaults.PushFirebaseServiceAccountPathConfigKey];

        if (enabled && !string.IsNullOrWhiteSpace(serviceAccountPath))
        {
            // FirebaseApp.Create throws if a default app already exists (e.g. a second host build
            // within the same test process); guard so registration stays idempotent.
            if (Firebase.FirebaseApp.DefaultInstance == null)
            {
                Firebase.FirebaseApp.Create(new Firebase.AppOptions
                {
                    Credential = GoogleCredential.FromFile(serviceAccountPath),
                });
            }

            services.AddSingleton<IFcmSender, FirebaseFcmSender>();
        }
        else
        {
            services.AddSingleton<IFcmSender, LoggingFcmSender>();
        }

        return services;
    }
}
