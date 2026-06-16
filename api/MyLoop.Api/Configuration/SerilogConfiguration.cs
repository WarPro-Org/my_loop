using MyLoop.Api.Constants;
using Serilog;
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

            config
                .ReadFrom.Configuration(context.Configuration)
                .ReadFrom.Services(services)
                .Enrich.FromLogContext()
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

            var seqUrl = context.Configuration["Seq:ServerUrl"];
            if (!string.IsNullOrWhiteSpace(seqUrl))
                config.WriteTo.Seq(seqUrl);
        });
}
