---
name: webapi-standards
description: Enterprise ASP.NET Core composition standards — keep Program.cs a thin composition root, register services via grouped extension methods, push config to the Options pattern, and keep Controllers thin. Use when adding/modifying startup, DI registration, middleware pipeline, or any code under api/MyLoop.Api/Configuration, Program.cs, or Controllers.
origin: MyLoop (staff-engineering standard)
---

# Web API Standards — Enterprise ASP.NET Core

Keeps the API's composition root small, intentional, and uniform. The #1 thing this
skill prevents is `Program.cs` decaying back into a god-file (it was decomposed in
commit `39c07f67d` — do not regress it).

## When to Activate

- Editing `Program.cs` or anything under `api/MyLoop.Api/Configuration/`
- Adding a new service, middleware, auth scheme, or hosted service to DI
- Adding/changing a Controller
- Introducing a new config value or feature flag

## Rule 1 — `Program.cs` is a composition root, nothing else

`Program.cs` may only: create the builder, register service groups, build the app,
wire the pipeline, and run. **No business logic, no inline lambdas with behaviour, no
literals, no `if` branches on environment beyond what an extension method hides.**

Target: **under ~40 lines.** The current shape is the reference:

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Host.AddMyLoopSerilog();
builder.Services
    .AddMyLoopDatabase(builder.Configuration)
    .AddMyLoopServices()
    .AddMyLoopAuthentication(builder.Configuration)
    .AddMyLoopRateLimiting()
    .AddMyLoopCors(builder.Configuration);
builder.Services.AddSignalR();
builder.Services.AddControllers();
var app = builder.Build();
app.UseMyLoopPipeline();
await app.InitializeDatabaseAsync();
app.Run();
```

If a change makes you add more than ~3 lines to `Program.cs`, that logic belongs in an
extension method under `Configuration/`.

## Rule 2 — Register by concern, via `IServiceCollection` extension methods

Every registration group lives in its own `*Extensions.cs` under `Configuration/`,
returns `IServiceCollection` for chaining, and is named `AddMyLoop<Concern>`.
Pipeline wiring lives in one `UseMyLoopPipeline` in `RequestPipelineExtensions.cs`.

```csharp
public static IServiceCollection AddMyLoopRateLimiting(this IServiceCollection services)
{
    // ... configure here, not in Program.cs
    return services;
}
```

Do **not** add a bare `services.AddX()` to `Program.cs` when it has options, policies,
or more than one related call — wrap it.

## Rule 3 — Config through the Options pattern, never inline literals

Bind configuration sections to strongly-typed options classes (`IOptions<T>`), validated
at startup (`.ValidateOnStart()`). No `Configuration["Some:Key"]` scattered through
services. No magic connection strings, timeouts, or limits in code — those are config
or `Constants/` (see `InfrastructureDefaults.cs`, `GameConstants.cs`).

## Rule 4 — Controllers stay thin

Controllers do: model binding, auth attributes, call **one** service method, map result
to an `IActionResult`/`TypedResults`. **No business logic, no EF queries, no SignalR
broadcasts in controllers.** Logic → `Services/`, data → `Data/`. Return typed results
with correct status codes (defer to `api-design` for the contract).

```csharp
[HttpPost(ApiRoutes.Loops.Claim)]
public async Task<IActionResult> Claim(ClaimLoopRequest request, CancellationToken ct)
{
    var result = await _loopService.ClaimAsync(request, ct); // one call
    return result.ToActionResult();                          // map, don't branch on internals
}
```

## Rule 5 — Cross-cutting concerns live in middleware/filters, not copied per-endpoint

Exception-to-ProblemDetails translation, request logging, correlation IDs, auth, and
rate limiting are pipeline concerns. If you find yourself repeating a try/catch or an
auth check in multiple controllers, lift it into `Middleware/` or a filter.

## Pre-PR Checklist

- [ ] `Program.cs` still reads as a composition root only (no logic, no literals, ~<40 lines)
- [ ] New registrations are grouped `AddMyLoop*` extension methods returning `IServiceCollection`
- [ ] Pipeline changes went through `UseMyLoopPipeline`, not raw `app.Use*` in `Program.cs`
- [ ] New config is a validated Options class, not inline `Configuration[...]` reads
- [ ] Controllers added/changed call exactly one service method and contain no business logic / EF / SignalR
- [ ] No magic numbers or strings — routes in `ApiRoutes`, tunables in `Constants/` or config
- [ ] Startup is deterministic: `ValidateOnStart` for required options; fail fast on misconfig
