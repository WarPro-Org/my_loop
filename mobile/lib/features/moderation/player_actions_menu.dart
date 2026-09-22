/// ⋮ menu on another player's profile: report their name, block/unblock them (DR-002b, #190).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/features/moderation/blocked_users.dart';
import 'package:myloop/shared/services/api_service.dart';

final _log = Logger('PlayerActions');

/// Why a name is being reported. [name] is the API wire value.
enum NameReportReason {
  offensive('Offensive name'),
  impersonation('Pretending to be someone else'),
  other('Something else');

  const NameReportReason(this.label);
  final String label;
}

const playerOptionsTooltip = 'Player options';
const reportNameLabel = 'Report name';
const blockPlayerLabel = 'Block player';
const unblockPlayerLabel = 'Unblock player';
const reportReasonPrompt = 'Why are you reporting this name?';
const reportThanksMessage = "Thanks — we'll review this name";
const reportOfflineError = "You're offline — connect to report a name";
const reportFailedError = "Couldn't send your report — try again";

/// Sends a report. Returns the message to show the player. Every accepted outcome reads the same
/// (the API deliberately answers repeats and some targets identically).
Future<String> submitNameReport(ApiService api, String userId, NameReportReason reason) async {
  try {
    await api.reportName(userId, reason.name);
    return reportThanksMessage;
  } catch (e, s) {
    if (isServerUnreachable(e)) return reportOfflineError;
    final serverReason = ApiService.extractApiError(e);
    if (serverReason == null) _log.warning('Name report failed unexpectedly', e, s);
    return serverReason ?? reportFailedError;
  }
}

enum _PlayerAction { report, block, unblock }

class PlayerActionsMenu extends ConsumerWidget {
  const PlayerActionsMenu({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBlocked = ref.watch(blockedUsersProvider).contains(userId);
    return PopupMenuButton<_PlayerAction>(
      tooltip: playerOptionsTooltip,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => _onSelected(context, ref, action),
      itemBuilder: (_) => [
        const PopupMenuItem(value: _PlayerAction.report, child: Text(reportNameLabel)),
        isBlocked
            ? const PopupMenuItem(value: _PlayerAction.unblock, child: Text(unblockPlayerLabel))
            : const PopupMenuItem(value: _PlayerAction.block, child: Text(blockPlayerLabel)),
      ],
    );
  }

  Future<void> _onSelected(BuildContext context, WidgetRef ref, _PlayerAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(blockedUsersProvider.notifier);
    switch (action) {
      case _PlayerAction.report:
        final reason = await _pickReason(context);
        if (reason == null) return;
        final message = await submitNameReport(ref.read(apiServiceProvider), userId, reason);
        messenger.showSnackBar(SnackBar(content: Text(message)));
      case _PlayerAction.block:
        final error = await notifier.block(userId);
        messenger.showSnackBar(SnackBar(content: Text(error ?? blockedConfirmation)));
      case _PlayerAction.unblock:
        final error = await notifier.unblock(userId);
        messenger.showSnackBar(SnackBar(content: Text(error ?? unblockedConfirmation)));
    }
  }

  Future<NameReportReason?> _pickReason(BuildContext context) => showModalBottomSheet<NameReportReason>(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Text(reportReasonPrompt, style: Theme.of(ctx).textTheme.titleLarge),
              ),
              for (final reason in NameReportReason.values)
                ListTile(
                  title: Text(reason.label),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.grey),
                  onTap: () => Navigator.pop(ctx, reason),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
}
