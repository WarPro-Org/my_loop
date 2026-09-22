using System.Reflection;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Infrastructure;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using MyLoop.Api.Constants;
using MyLoop.Api.Controllers;
using MyLoop.Api.Entities;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Models;
using MyLoop.Api.Options;
using MyLoop.Api.Services;
using MyLoop.Api.Services.Moderation;
using MyLoop.Api.Services.Moderation.Alerts;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// DR-002b / #190 — the Docker-free parts of name moderation: who is a moderator, how alerts are
/// delivered, what the endpoints answer, and that the rename lock is enforced server-side.
/// The Postgres-dependent report/hide/restore flow is covered by ModerationFlowTests.
/// </summary>
public class ModerationUnitTests
{
    private const string ModeratorUid = "mod-uid";

    private static IModeratorDirectory Directory(params string[] uids)
    {
        var monitor = new Mock<IOptionsMonitor<ModerationOptions>>();
        monitor.Setup(m => m.CurrentValue).Returns(new ModerationOptions { ModeratorUids = uids });
        return new ModeratorDirectory(monitor.Object);
    }

    // ---- Moderator policy ------------------------------------------------------------------

    [Theory]
    [InlineData(ModeratorUid, true)]
    [InlineData("player-uid", false)]
    [InlineData(null, false)]
    public async Task Moderator_policy_succeeds_only_for_allowlisted_uids(string? callerUid, bool expected)
    {
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.FirebaseUid).Returns(callerUid);
        var handler = new ModeratorAuthorizationHandler(currentUser.Object, Directory(ModeratorUid));
        var context = new AuthorizationHandlerContext([new ModeratorRequirement()], new ClaimsPrincipal(), null);

        await handler.HandleAsync(context);

        Assert.Equal(expected, context.HasSucceeded);
    }

    [Fact]
    public void Moderator_uid_match_is_exact()
    {
        Assert.False(Directory(ModeratorUid).IsModerator("MOD-UID"));
        Assert.False(Directory().IsModerator(ModeratorUid));
    }

    [Fact]
    public void Every_moderation_endpoint_requires_the_moderator_policy()
    {
        var attribute = typeof(ModerationController).GetCustomAttribute<AuthorizeAttribute>();
        Assert.Equal(AuthorizationPolicies.Moderator, attribute?.Policy);
        var anonymous = typeof(ModerationController).GetMethods()
            .Where(m => m.GetCustomAttribute<AllowAnonymousAttribute>() != null);
        Assert.Empty(anonymous);
    }

    // ---- Alerts --------------------------------------------------------------------------

    private sealed class RecordingChannel(string name, bool fail = false) : IModerationAlertChannel
    {
        public List<ModerationAlert> Sent { get; } = [];
        public string Name => name;
        public Task SendAsync(ModerationAlert alert, CancellationToken cancellationToken)
        {
            if (fail) throw new InvalidOperationException("smtp down");
            Sent.Add(alert);
            return Task.CompletedTask;
        }
    }

    private static ModerationAlert SampleAlert() =>
        ModerationAlert.ForCase(ModerationAlertKind.AutoHidden, Guid.NewGuid(), Guid.NewGuid(), "BadName", 3);

    [Fact]
    public async Task A_failing_channel_does_not_stop_delivery_to_the_others()
    {
        var broken = new RecordingChannel("email", fail: true);
        var working = new RecordingChannel("slack");
        var queue = new ModerationAlertQueue(NullLogger<ModerationAlertQueue>.Instance);
        var dispatcher = new ModerationAlertDispatcher(queue, [broken, working], NullLogger<ModerationAlertDispatcher>.Instance);

        await dispatcher.DeliverAsync(SampleAlert(), CancellationToken.None);

        Assert.Single(working.Sent);
    }

    [Fact]
    public async Task Raised_alerts_are_delivered_by_the_background_dispatcher()
    {
        var channel = new RecordingChannel("email");
        var queue = new ModerationAlertQueue(NullLogger<ModerationAlertQueue>.Instance);
        var dispatcher = new ModerationAlertDispatcher(queue, [channel], NullLogger<ModerationAlertDispatcher>.Instance);
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));

        await dispatcher.StartAsync(cts.Token);
        queue.Raise(SampleAlert());
        while (channel.Sent.Count == 0 && !cts.IsCancellationRequested) await Task.Delay(10, cts.Token);
        await dispatcher.StopAsync(CancellationToken.None);

        Assert.Single(channel.Sent);
    }

    [Fact]
    public void Raise_never_throws_when_the_queue_is_full()
    {
        var queue = new ModerationAlertQueue(NullLogger<ModerationAlertQueue>.Instance);
        for (var i = 0; i < InfrastructureDefaults.ModerationAlertQueueCapacity + 10; i++)
            queue.Raise(SampleAlert());
    }

    [Fact]
    public void Alert_email_names_the_reported_name_and_case_but_never_a_reporter()
    {
        var alert = ModerationAlert.ForCase(ModerationAlertKind.AutoHidden, Guid.NewGuid(), Guid.NewGuid(), "BadName", 3);

        var subject = SmtpModerationAlertChannel.BuildSubject(alert);
        var body = SmtpModerationAlertChannel.BuildBody(alert);

        Assert.Contains("BadName", subject);
        Assert.Contains(alert.CaseId!.Value.ToString(), body);
        Assert.DoesNotContain("reporter", body, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Rescan_digest_lists_every_hidden_name()
    {
        var alert = new ModerationAlert(ModerationAlertKind.RescanDigest, null, null, null, 0, ["line one", "line two"]);
        var body = SmtpModerationAlertChannel.BuildBody(alert);
        Assert.Contains("line one", body);
        Assert.Contains("line two", body);
        Assert.Contains("2 name(s)", SmtpModerationAlertChannel.BuildSubject(alert));
    }

    [Theory]
    [InlineData("", "", 0, true)]                       // disabled: nothing required
    [InlineData("smtp.example.com", "a@b.c", 1, true)]
    [InlineData("smtp.example.com", "", 1, false)]      // no sender
    [InlineData("smtp.example.com", "a@b.c", 0, false)] // no recipient
    public void Email_options_require_sender_and_recipient_only_when_enabled(string host, string from, int recipients, bool valid)
    {
        var options = new ModerationEmailOptions
        {
            Host = host, From = from, To = Enumerable.Repeat("mods@example.com", recipients).ToArray(),
        };
        Assert.Equal(valid, options.IsValid());
    }

    // ---- Placeholder ---------------------------------------------------------------------

    [Fact]
    public void Placeholder_is_stable_and_cannot_be_chosen_as_a_name()
    {
        var id = Guid.Parse("a7f3c2d1-0000-0000-0000-000000000000");

        var placeholder = NameModeration.PlaceholderFor(id);

        Assert.Equal("Player#A7F3", placeholder);
        Assert.NotNull(new ValidationService().ValidateDisplayName(placeholder)); // '#' is not allowed
    }

    // ---- Report endpoint -----------------------------------------------------------------

    private static NameReportsController ReportsController(NameReportOutcome outcome, Guid? callerId)
    {
        var reports = new Mock<INameReportService>();
        reports.Setup(r => r.ReportAsync(It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<NameReportReason>())).ReturnsAsync(outcome);
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(callerId);
        return new NameReportsController(reports.Object, currentUser.Object);
    }

    [Theory]
    [InlineData(NameReportOutcome.Accepted, 204)]
    [InlineData(NameReportOutcome.Ignored, 204)]  // indistinguishable from accepted — reveals nothing
    [InlineData(NameReportOutcome.SelfReport, 400)]
    [InlineData(NameReportOutcome.NotFound, 404)]
    [InlineData(NameReportOutcome.DailyLimitReached, 429)]
    public async Task Report_outcomes_map_to_status_codes(NameReportOutcome outcome, int status)
    {
        var result = await ReportsController(outcome, Guid.NewGuid())
            .Report(Guid.NewGuid(), new NameReportRequest { Reason = NameReportReason.Offensive });

        Assert.Equal(status, Assert.IsAssignableFrom<IStatusCodeActionResult>(result).StatusCode);
    }

    [Fact]
    public async Task Report_without_a_resolved_caller_is_unauthorized()
    {
        var result = await ReportsController(NameReportOutcome.Accepted, callerId: null)
            .Report(Guid.NewGuid(), new NameReportRequest { Reason = NameReportReason.Offensive });
        Assert.IsType<UnauthorizedResult>(result);
    }

    [Theory]
    [InlineData("offensive", NameReportReason.Offensive)]
    [InlineData("impersonation", NameReportReason.Impersonation)]
    [InlineData("other", NameReportReason.Other)]
    public void Report_reason_is_read_from_the_lowercase_wire_value(string wire, NameReportReason expected)
    {
        var request = JsonSerializer.Deserialize<NameReportRequest>(
            $$"""{"reason":"{{wire}}"}""", new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Assert.Equal(expected, request!.Reason);
    }

    [Fact]
    public void Unknown_report_reason_is_rejected()
    {
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<NameReportRequest>(
            """{"reason":"spam"}""", new JsonSerializerOptions(JsonSerializerDefaults.Web)));
    }

    // ---- Moderation endpoints ------------------------------------------------------------

    [Fact]
    public async Task Unknown_case_status_filter_is_a_bad_request()
    {
        var controller = new ModerationController(Mock.Of<IModerationService>(), Mock.Of<ICurrentUser>());
        Assert.IsType<BadRequestObjectResult>(await controller.ListCases("bogus"));
    }

    [Theory]
    [InlineData(ModerationDecisionOutcome.Done, 204)]
    [InlineData(ModerationDecisionOutcome.NotFound, 404)]
    [InlineData(ModerationDecisionOutcome.InvalidState, 409)]
    public async Task Decision_outcomes_map_to_status_codes(ModerationDecisionOutcome outcome, int status)
    {
        var moderation = new Mock<IModerationService>();
        moderation.Setup(m => m.RestoreAsync(It.IsAny<Guid>(), ModeratorUid)).ReturnsAsync(outcome);
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.FirebaseUid).Returns(ModeratorUid);

        var result = await new ModerationController(moderation.Object, currentUser.Object).Restore(Guid.NewGuid());

        Assert.Equal(status, Assert.IsAssignableFrom<IStatusCodeActionResult>(result).StatusCode);
    }

    // ---- Block endpoints -----------------------------------------------------------------

    private static BlocksController BlocksControllerFor(BlockOutcome outcome, Guid? callerId)
    {
        var blocks = new Mock<IBlockService>();
        blocks.Setup(b => b.BlockAsync(It.IsAny<Guid>(), It.IsAny<Guid>())).ReturnsAsync(outcome);
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(callerId);
        return new BlocksController(blocks.Object, currentUser.Object);
    }

    [Theory]
    [InlineData(BlockOutcome.Done, 204)]
    [InlineData(BlockOutcome.SelfBlock, 400)]
    [InlineData(BlockOutcome.NotFound, 404)]
    [InlineData(BlockOutcome.LimitReached, 409)]
    public async Task Block_outcomes_map_to_status_codes(BlockOutcome outcome, int status)
    {
        var result = await BlocksControllerFor(outcome, Guid.NewGuid()).Block(Guid.NewGuid());
        Assert.Equal(status, Assert.IsAssignableFrom<IStatusCodeActionResult>(result).StatusCode);
    }

    [Fact]
    public async Task Block_endpoints_require_a_resolved_caller()
    {
        var controller = BlocksControllerFor(BlockOutcome.Done, callerId: null);
        Assert.IsType<UnauthorizedResult>(await controller.Block(Guid.NewGuid()));
        Assert.IsType<UnauthorizedResult>(await controller.Unblock(Guid.NewGuid()));
        Assert.IsType<UnauthorizedResult>((await controller.List()).Result);
    }

    [Fact]
    public async Task Block_list_returns_the_callers_blocks()
    {
        var me = Guid.NewGuid();
        var blocked = Guid.NewGuid();
        var blocks = new Mock<IBlockService>();
        blocks.Setup(b => b.ListBlockedAsync(me)).ReturnsAsync([blocked]);
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(me);

        var result = await new BlocksController(blocks.Object, currentUser.Object).List();

        var body = Assert.IsType<BlockListResponse>(Assert.IsType<OkObjectResult>(result.Result).Value);
        Assert.Equal([blocked], body.BlockedUserIds);
    }

    // ---- Rename lock (PATCH /api/users/{id}) ---------------------------------------------

    private static UsersController UsersControllerFor(Guid userId)
    {
        var stored = new User { Id = userId, FirebaseUid = "uid", DisplayName = "Robin", Color = "#00D4AA" };
        var users = new Mock<IUserService>();
        users.Setup(u => u.UpdateProfile(userId, It.IsAny<UpdateUserRequest>())).ReturnsAsync(stored);
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(userId);
        return new UsersController(users.Object, new ValidationService(), Mock.Of<IPushNotificationService>(),
            geocoding: null!, db: null!, currentUser.Object,
            Mock.Of<IMissionService>(), Mock.Of<IAchievementService>(), Mock.Of<ITerritoryService>(),
            NullLogger<UsersController>.Instance);
    }

    private static Mock<IModerationService> RenameGate(Guid userId, RenameCheck check)
    {
        var moderation = new Mock<IModerationService>();
        moderation.Setup(m => m.CheckRenameAsync(userId, It.IsAny<string>())).ReturnsAsync(check);
        return moderation;
    }

    [Fact]
    public async Task Rename_while_locked_is_refused_with_name_locked()
    {
        var id = Guid.NewGuid();

        var result = await UsersControllerFor(id).Update(id, new UpdateUserRequest { DisplayName = "Kai" },
            RenameGate(id, RenameCheck.Locked).Object);

        var conflict = Assert.IsType<ConflictObjectResult>(result);
        Assert.Equal("name_locked", Assert.IsType<NameLockedError>(conflict.Value).Code);
    }

    [Fact]
    public async Task Renaming_back_to_a_name_a_moderator_removed_is_refused()
    {
        var id = Guid.NewGuid();

        var result = await UsersControllerFor(id).Update(id, new UpdateUserRequest { DisplayName = "Kai" },
            RenameGate(id, RenameCheck.RemovedName).Object);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task An_allowed_rename_is_saved()
    {
        var id = Guid.NewGuid();

        var result = await UsersControllerFor(id).Update(id, new UpdateUserRequest { DisplayName = "Kai" },
            RenameGate(id, RenameCheck.Allowed).Object);

        Assert.IsType<OkObjectResult>(result);
    }

    [Fact]
    public async Task Changing_only_avatar_or_colour_skips_the_rename_gate()
    {
        var id = Guid.NewGuid();
        var moderation = RenameGate(id, RenameCheck.Locked);

        var result = await UsersControllerFor(id).Update(id, new UpdateUserRequest { AvatarId = 3 }, moderation.Object);

        Assert.IsType<OkObjectResult>(result);
        moderation.Verify(m => m.CheckRenameAsync(It.IsAny<Guid>(), It.IsAny<string>()), Times.Never);
    }
}
