/// The game rules the app uses right now (FR1).
///
/// Always synchronous and always usable: it starts with the built-in copy, switches to the
/// saved copy once read from disk, and then to the server's rules when a refresh finds they changed.
/// A walk never waits on the network for rules.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:myloop/shared/services/api_service.dart';

import 'game_rules.dart';
import 'rules_source.dart';
import 'rules_store.dart';

final _log = Logger('GameRules');

final rulesStoreProvider = Provider<RulesStore>((ref) => FileRulesStore());

final rulesSourceProvider =
    Provider<RulesSource>((ref) => ApiRulesSource(ref.read(apiServiceProvider)));

final gameRulesProvider = NotifierProvider<GameRulesNotifier, GameRules>(GameRulesNotifier.new);

class GameRulesNotifier extends Notifier<GameRules> {
  Future<void>? _loadSaved;

  @override
  GameRules build() {
    _loadSaved = _useSavedCopy();
    unawaited(refresh());
    return defaultGameRules;
  }

  Future<void> _useSavedCopy() async {
    final saved = await ref.read(rulesStoreProvider).load();
    if (saved != null) state = saved;
  }

  /// Asks the server whether the rules changed and saves any new copy. Called on app start and on every
  /// login/resume. Offline or signed out → keeps the current rules.
  Future<void> refresh() async {
    await _loadSaved;
    try {
      final changed = await ref.read(rulesSourceProvider).fetchIfChanged(state.version);
      if (changed == null) return;
      await ref.read(rulesStoreProvider).save(changed);
      state = changed;
      _log.info('Game rules updated to version ${changed.version}');
    } on DioException catch (e) {
      // Offline, signed out (401) or server down: normal — keep the rules we have.
      _log.fine('Game rules refresh skipped; keeping version ${state.version}', e);
    } catch (e, stack) {
      // A malformed response or a failed save: keep the current rules but surface it.
      _log.warning('Game rules refresh failed; keeping version ${state.version}', e, stack);
    }
  }
}
