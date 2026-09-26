/// The game rules the app uses right now (FR1).
///
/// Always synchronous and always usable: it starts with the built-in copy, switches to the
/// saved copy once read from disk, and then to the server's rules when a refresh finds they changed.
/// A walk never waits on the network for rules, and a running walk keeps the rules it started
/// with (see JourneyController), so a mid-walk update only affects the next walk (#20).
library;

import 'dart:async';

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

  Future<void>? _inFlight;
  bool _runAgain = false;

  @override
  GameRules build() {
    _loadSaved = _useSavedCopy();
    unawaited(refresh());
    return defaultGameRules;
  }

  /// Completes once the saved copy has been read (or found missing), so a caller that must not
  /// start on the built-in copy — e.g. a walk started right after launch — can wait for it.
  Future<void> get ready => _loadSaved ?? Future.value();

  Future<void> _useSavedCopy() async {
    try {
      final saved = await ref.read(rulesStoreProvider).load();
      if (saved == null) return;
      _tag = saved.tag;
      state = saved.rules;
    } on Exception catch (e, stack) {
      // Storage itself unavailable (e.g. no documents directory): the built-in rules are always
      // a safe fallback, and refresh() must still run instead of failing on every app open.
      _log.warning('Saved game rules unavailable; using built-in copy', e, stack);
    }
  }

  /// Asks the server whether the rules changed; applies any new copy and tries to save it. Called on app start and on every
  /// login/resume. Offline or signed out → keeps the current rules.
  ///
  /// App start and hydration often call this at the same moment. Only one request runs at a
  /// time; a call that arrives mid-request makes it run once more afterwards, because things may
  /// have changed since it started (e.g. the user signed in after a request that got a 401).
  Future<void> refresh() {
    if (_inFlight case final running?) {
      _runAgain = true;
      return running;
    }
    return _inFlight = _refreshUntilSettled();
  }

  Future<void> _refreshUntilSettled() async {
    try {
      do {
        _runAgain = false;
        await _refresh();
      } while (_runAgain);
    } finally {
      // Cleared in the same step as the last _runAgain check, so no call can slip in between.
      _inFlight = null;
    }
  }

  Future<void> _refresh() async {
    await _loadSaved;
    try {
      final changed = await ref.read(rulesSourceProvider).fetchIfChanged(_tag);
      if (changed == null) return;
      // Apply first: the new rules are valid even if saving them fails.
      _tag = changed.tag;
      state = changed.rules;
      _log.info('Game rules updated to version ${changed.rules.version}');
      await _save(changed);
    } on DioException catch (e) {
      // Offline, signed out (401) or server down: normal — keep the rules we have.
      _log.fine('Game rules refresh skipped; keeping version ${state.version}', e);
    } on FormatException catch (e, stack) {
      // The server sent rules the app can't read: keep the current rules but surface it.
      _log.warning('Game rules response unreadable; keeping version ${state.version}', e, stack);
    }
  }

  Future<void> _save(SavedRules rules) async {
    try {
      await ref.read(rulesStoreProvider).save(rules);
    } on Exception catch (e, stack) {
      // Storage unavailable: the rules still apply for this session. The saved copy stays older,
      // so the next launch starts from it and refresh() fetches these rules again.
      _log.warning('Game rules could not be saved; using them for this session only', e, stack);
    }
  }
}
