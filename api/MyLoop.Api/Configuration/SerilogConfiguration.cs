using MyLoop.Api.Constants;
using Serilog;
using Serilog.Events;
using Serilog.Formatting.Compact;

namespace MyLoop.Api.Configuration;

/// <summary>
/// Serilog host configuration. Stable contract: structured events enriched with the W3C trace id
/// + caller, emitted as JSON. Only the sinks below change as we scale (file → Seq → OTLP/Grafana)
/// — never application code.
///   • Console: human-readable, surfaces the trace id, for live tailing.
///   • File:    daily rolling compact JSON so EVERY enriched property (trace id, caller, status,
///              elapsed) is captured and greppable when reconstructing a beta bug after the fact.
///   • Seq:     optional self-hosted search UI; only wired when "Seq:ServerUrl" is configured, and
///              the sink no-ops if Seq is unreachable so a missing container never breaks the app.
/// </summary>
public static class SerilogConfiguration
{
    public static IHostBuilder AddMyLoopSerilog(this IHostBuilder host) =>
        host.UseSerilog((context, services, config) =>
        {
            // Anchor the log path to the content root (not the relative CWD): under systemd or a
            // container, CWD is often "/" which isn't writable, and Serilog swallows the open
            // failure to SelfLog — the durable log would silently write nowhere. Allow ops to
            // override the directory (e.g. /var/log/myloop) via "Serilog:LogDirectory".
            var logDirectory = context.Configuration["Serilog:LogDirectory"]
                ?? Path.Combine(context.HostingEnvironment.ContentRootPath, InfrastructureDefaults.LogDirectoryName);
            // Mock-simulator logs (#29) live in a sibling directory so beta logs stay free of
            // synthetic-walk noise; ops can relocate them independently of the real logs.
            var mockLogDirectory = context.Configuration["Serilog:MockLogDirectory"]
                ?? Path.Combine(context.HostingEnvironment.ContentRootPath, InfrastructureDefaults.MockLogDirectoryName);

            var seqUrl = context.Configuration["Seq:ServerUrl"];

            config
                .ReadFrom.Configuration(context.Configuration)
                .ReadFrom.Services(services)
                .Enrich.FromLogContext()
                // Real traffic — every event EXCEPT mock-simulator requests. Keeps the durable beta
                // logs (and Seq) free of synthetic-walk noise (#29).
                .WriteTo.Logger(real =>
                {
                    real
                        .Filter.ByExcluding(IsMockEvent)
                        .WriteTo.Console(
                            outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {TraceId} {Message:lj}{NewLine}{Exception}")
                        .WriteTo.File(
                            formatter: new CompactJsonFormatter(),
                            path: Path.Combine(logDirectory, InfrastructureDefaults.LogFileNamePattern),
                            rollingInterval: RollingInterval.Day,
                            retainedFileCountLimit: InfrastructureDefaults.LogRetainedFileCountLimit,
                            fileSizeLimitBytes: InfrastructureDefaults.LogFileSizeLimitBytes,
                            rollOnFileSizeLimit: true,
                            shared: true);

                    if (!string.IsNullOrWhiteSpace(seqUrl))
                        real.WriteTo.Seq(seqUrl);
                })
                // Mock-simulator traffic — segregated rolling file, identical format, never mixed
                // into the real logs above (#29).
                .WriteTo.Logger(mock => mock
                    .Filter.ByIncludingOnly(IsMockEvent)
                    .WriteTo.File(
                        formatter: new CompactJsonFormatter(),
                        path: Path.Combine(mockLogDirectory, InfrastructureDefaults.MockLogFileNamePattern),
                        rollingInterval: RollingInterval.Day,
                        retainedFileCountLimit: InfrastructureDefaults.LogRetainedFileCountLimit,
                        fileSizeLimitBytes: InfrastructureDefaults.LogFileSizeLimitBytes,
                        rollOnFileSizeLimit: true,
                        shared: true));
        });

    /// <summary>
    /// A mock-simulator event is one tagged by <c>MockLogContextMiddleware</c> with the
    /// <see cref="InfrastructureDefaults.MockLogContextProperty"/> property (#29).
    /// </summary>
    private static bool IsMockEvent(LogEvent logEvent) =>
        logEvent.Properties.ContainsKey(InfrastructureDefaults.MockLogContextProperty);
}
