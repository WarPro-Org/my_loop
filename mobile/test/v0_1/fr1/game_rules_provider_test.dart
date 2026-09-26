/// FR1 — the app always has usable rules: built-in → saved copy → server update.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/rules/game_rules.dart';
import 'package:myloop/shared/rules/game_rules_provider.dart';
import 'package:myloop/shared/rules/rules_source.dart';
import 'package:myloop/shared/rules/rules_store.dart';

SavedRules _version(int v) =>
    SavedRules(GameRules.fromJson({...defaultGameRules.toJson(), 'version': v}), 'tag-$v');

class _MemoryStore implements RulesStore {
  _MemoryStore([this.saved]);
  SavedRules? saved;
  int saves = 0;
  @override
  Future<SavedRules?> load() async => saved;
  @override
  Future<void> save(SavedRules rules) async {
    saved = rules;
    saves++;
  }
}

class _BrokenStore implements RulesStore {
  int saveAttempts = 0;
  @override
  Future<SavedRules?> load() async => throw Exception('no documents directory');
  @override
  Future<void> save(SavedRules rules) async {
    saveAttempts++;
    throw Exception('no documents directory');
  }
}

class _FakeSource implements RulesSource {
  _FakeSource({this.serverRules, this.offline = false});
  final SavedRules? serverRules;
  final bool offline;
  /// Fingerprint sent with each request, in order.
  final askedWithTags = <String?>[];
  int get fetches => askedWithTags.length;
  @override
  Future<SavedRules?> fetchIfChanged(String? knownTag) async {
    askedWithTags.add(knownTag);
    if (offline) throw DioException(requestOptions: RequestOptions(), message: 'no internet');
    return serverRules == null || serverRules!.tag == knownTag ? null : serverRules;
  }
}

Future<GameRules> _settle(ProviderContainer container) async {
  container.read(gameRulesProvider);
  await container.read(gameRulesProvider.notifier).refresh();
  return container.read(gameRulesProvider);
}

ProviderContainer _container(RulesStore store, RulesSource source) {
  final container = ProviderContainer(overrides: [
    rulesStoreProvider.overrideWithValue(store),
    rulesSourceProvider.overrideWithValue(source),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('first launch with no saved copy asks the server without a fingerprint', () async {
    final source = _FakeSource(serverRules: _version(2));
    final container = _container(_MemoryStore(), source);

    expect((await _settle(container)).version, 2);
    expect(source.askedWithTags.first, isNull);
  });

  test('first launch with no internet uses the built-in copy', () async {
    final container = _container(_MemoryStore(), _FakeSource(offline: true));

    expect(container.read(gameRulesProvider).version, defaultGameRules.version);
    expect((await _settle(container)).version, defaultGameRules.version);
  });

  test('offline with a saved copy uses the saved copy', () async {
    final container = _container(_MemoryStore(_version(5)), _FakeSource(offline: true));

    expect((await _settle(container)).version, 5);
  });

  test('changed server rules replace the current ones and are saved', () async {
    final store = _MemoryStore(_version(5));
    final source = _FakeSource(serverRules: _version(6));
    final container = _container(store, source);

    final rules = await _settle(container);

    expect(rules.version, 6);
    expect(store.saved?.rules.version, 6);
    expect(source.askedWithTags.first, 'tag-5');
  });

  test('up-to-date app asks with its saved fingerprint and saves nothing', () async {
    final store = _MemoryStore(_version(5));
    final source = _FakeSource(serverRules: _version(5));
    final container = _container(store, source);

    final rules = await _settle(container);

    expect(rules.version, 5);
    expect(source.askedWithTags.first, 'tag-5');
    expect(store.saves, 0);
  });

  test('broken phone storage still falls back to built-in rules and checks the server', () async {
    final source = _FakeSource(serverRules: _version(3));
    final store = _BrokenStore();
    final container = ProviderContainer(overrides: [
      rulesStoreProvider.overrideWithValue(store),
      rulesSourceProvider.overrideWithValue(source),
    ]);
    addTearDown(container.dispose);

    // _settle awaits refresh(): it must complete normally, with the server's rules applied.
    expect((await _settle(container)).version, 3);
    // Building the provider starts a refresh and _settle asks for another. The second run sees
    // the new fingerprint, gets "not modified" and saves nothing.
    expect(store.saveAttempts, 1);
  });

  test('overlapping refreshes never fetch in parallel or save twice', () async {
    final store = _MemoryStore();
    final source = _FakeSource(serverRules: _version(4));
    final container = _container(store, source);

    container.read(gameRulesProvider);
    final notifier = container.read(gameRulesProvider.notifier);
    await Future.wait([notifier.refresh(), notifier.refresh()]);

    expect(container.read(gameRulesProvider).version, 4);
    expect(store.saves, 1);
    expect(source.fetches, lessThanOrEqualTo(2));
  });

  test('a refresh after login is not lost behind a signed-out request that got a 401', () async {
    final source = _ScriptedSource();
    final container = _container(_MemoryStore(), source);

    container.read(gameRulesProvider); // app start: signed out
    await pumpEventQueue();
    final loginRefresh = container.read(gameRulesProvider.notifier).refresh(); // after login

    source.first.completeError(DioException(requestOptions: RequestOptions(), message: '401'));
    await loginRefresh;

    expect(source.fetches, 2);
    expect(container.read(gameRulesProvider).version, 4);
  });
}

/// First call waits on [first] (the signed-out request); later calls return rules version 4.
class _ScriptedSource implements RulesSource {
  final first = Completer<SavedRules?>();
  int fetches = 0;
  @override
  Future<SavedRules?> fetchIfChanged(String? knownTag) {
    fetches++;
    return fetches == 1 ? first.future : Future.value(_version(4));
  }
}
