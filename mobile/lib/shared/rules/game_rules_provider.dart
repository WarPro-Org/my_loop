/// The game rules the app uses right now (FR1).
///
/// Always synchronous and always usable: it starts with the built-in copy, switches to the
/// saved copy once read from disk, and then to the server's rules when a refresh finds they changed.
/// A walk never waits on the network for rules, and a running walk keeps the rules it started
/// with (see JourneyController), so a mid-walk update only affects the next walk (#20).
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:myloop/shared/services/api_service.dart';

import 'package:myloop/shared/rules/game_rules.dart';
import 'package:myloop/shared/rules/rules_source.dart';
import 'package:myloop/shared/rules/rules_store.dart';

final _log = Logger('GameRules');

final rulesStoreProvider = Provider<RulesStore>((ref) => FileRulesStore());

final rulesSourceProvider =
    Provider<RulesSource>((ref) => ApiRulesSource(ref.read(apiServiceProvider)));

final gameRulesProvider = NotifierProvider<GameRulesNotifier, GameRules>(GameRulesNotifier.new);

class GameRulesNotifier extends Notifier<GameRules> {
  Future<void>? _loadSaved;

  /// Server fingerprint of [state]; null while on the built-in copy.
  String? _tag;

  @override
  GameRules build() {
    _loadSaved = _useSavedCopy();
    unawaited(refresh());
    return defaultGameRules;
  }

  Future<void> _useSavedCopy() async {
    final saved = await ref.read(rulesStoreProvider).load();
    if (saved == null) return;
    _tag = saved.tag;
    state = saved.rules;
  }

  /// Asks the server whether the rules changed and saves any new copy. Called on app start and on every
  /// login/resume. Offline or signed out → keeps the current rules.
  Future<void> refresh() async {
    await _loadSaved;
    try {
      final changed = await ref.read(rulesSourceProvider).fetchIfChanged(_tag);
      if (changed == null) return;
      await ref.read(rulesStoreProvider).save(changed);
      _tag = changed.tag;
      state = changed.rules;
      _log.info('Game rules updated to version ${changed.rules.version}');
    } on DioException catch (e) {
      // Offline, signed out (401) or server down: normal — keep the rules we have.
      _log.fine('Game rules refresh skipped; keeping version ${state.version}', e);
    } on FormatException catch (e, stack) {
      // The server sent rules the app can't read: keep the current rules but surface it.
      _log.warning('Game rules response unreadable; keeping version ${state.version}', e, stack);
    } on FileSystemException catch (e, stack) {
      // New rules arrived but couldn't be saved: keep the current rules, retry next refresh.
      _log.warning('Game rules could not be saved; keeping version ${state.version}', e, stack);
    }
  }
}
