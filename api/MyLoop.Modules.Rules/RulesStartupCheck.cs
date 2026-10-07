using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace MyLoop.Modules.Rules;

/// <summary>
/// Builds <see cref="IRuleSettings"/> while the server starts, so anything that fails while
/// building it stops startup instead of turning the first rules request into a 500.
/// </summary>
internal sealed class RulesStartupCheck(IServiceProvider services) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        services.GetRequiredService<IRuleSettings>();
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
