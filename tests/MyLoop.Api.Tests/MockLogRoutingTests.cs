using MyLoop.Api.Constants;
using Serilog;
using Serilog.Context;
using Serilog.Formatting.Compact;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Locks in the user-visible promise of #29: events tagged <c>IsMock</c> land ONLY in the
/// MockLogs sink and normal events land ONLY in the real-logs sink — no cross-contamination.
/// Mirrors the two filtered sub-loggers in <c>SerilogConfiguration</c>, sharing the production
/// constant so the property name can't silently drift.
/// </summary>
public class MockLogRoutingTests
{
    [Fact]
    public void Mock_events_go_to_MockLogs_only_and_real_events_to_real_logs_only()
    {
        var realDir = Path.Join(Path.GetTempPath(), "myloop-real-" + Guid.NewGuid().ToString("N"));
        var mockDir = Path.Join(Path.GetTempPath(), "myloop-mock-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(realDir);
        Directory.CreateDirectory(mockDir);

        const string realMarker = "real-claim-event";
        const string mockMarker = "mock-walk-event";

        try
        {
            var logger = new LoggerConfiguration()
                .Enrich.FromLogContext()
                .WriteTo.Logger(real => real
                    .Filter.ByExcluding(e => e.Properties.ContainsKey(InfrastructureDefaults.MockLogContextProperty))
                    .WriteTo.File(new CompactJsonFormatter(), Path.Join(realDir, "myloop-.log"),
                        rollingInterval: RollingInterval.Day))
                .WriteTo.Logger(mock => mock
                    .Filter.ByIncludingOnly(e => e.Properties.ContainsKey(InfrastructureDefaults.MockLogContextProperty))
                    .WriteTo.File(new CompactJsonFormatter(), Path.Join(mockDir, "mock-.log"),
                        rollingInterval: RollingInterval.Day))
                .CreateLogger();

            logger.Information(realMarker);
            using (LogContext.PushProperty(InfrastructureDefaults.MockLogContextProperty, true))
            {
                logger.Information(mockMarker);
            }
            logger.Dispose();

            var realContents = File.ReadAllText(Directory.GetFiles(realDir).Single());
            var mockContents = File.ReadAllText(Directory.GetFiles(mockDir).Single());

            Assert.Contains(realMarker, realContents);
            Assert.DoesNotContain(mockMarker, realContents);

            Assert.Contains(mockMarker, mockContents);
            Assert.DoesNotContain(realMarker, mockContents);
        }
        finally
        {
            Directory.Delete(realDir, recursive: true);
            Directory.Delete(mockDir, recursive: true);
        }
    }
}
