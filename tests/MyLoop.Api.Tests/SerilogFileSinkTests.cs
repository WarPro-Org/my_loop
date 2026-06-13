using Serilog;
using Serilog.Context;
using Serilog.Formatting.Compact;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Locks in the core promise of the logging design: a durable file line carries the
/// trace id pushed via <see cref="LogContext"/>, so one id greps across a whole
/// request. Mirrors the sink configuration in Program.cs.
/// </summary>
public class SerilogFileSinkTests
{
    [Fact]
    public void File_sink_writes_json_lines_carrying_the_trace_id()
    {
        var dir = Path.Combine(Path.GetTempPath(), "myloop-log-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, "test-.log");

        try
        {
            var logger = new LoggerConfiguration()
                .Enrich.FromLogContext()
                .WriteTo.File(new CompactJsonFormatter(), path, rollingInterval: RollingInterval.Day)
                .CreateLogger();

            using (LogContext.PushProperty("TraceId", "0af7651916cd43dd8448eb211c80319c"))
            {
                logger.Information("Claim processed for {UserId}", "user-42");
            }

            logger.Dispose(); // flush + release the file

            var written = Directory.GetFiles(dir).Single();
            var contents = File.ReadAllText(written);

            Assert.Contains("0af7651916cd43dd8448eb211c80319c", contents);
            Assert.Contains("user-42", contents);
            Assert.Contains("\"TraceId\"", contents); // structured, not just substring luck
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }
}
