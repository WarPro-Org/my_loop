/// FR1 — the app always has usable rules: built-in → saved copy → server update.
library;

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
  String? askedWithTag;
  @override
  Future<SavedRules?> fetchIfChanged(String? knownTag) async {
    askedWithTag = knownTag;
    if (offline) throw DioException(requestOptions: RequestOptions(), message: 'no internet');
    return serverRules == null || serverRules!.tag == knownTag ? null : serverRules;
  }
}

Future<GameRules> _settle(ProviderContainer container) async {
  container.read(gameRulesProvider);
  await container.read(gameRulesProvider.notifier).refresh();
  return container.read(gameRulesProvider);
}

ProviderContainer _container(_MemoryStore store, _FakeSource source) {
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
    expect(source.askedWithTag, isNull);
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
    expect(source.askedWithTag, 'tag-5');
  });

  test('up-to-date app asks with its saved fingerprint and saves nothing', () async {
    final store = _MemoryStore(_version(5));
    final source = _FakeSource(serverRules: _version(5));
    final container = _container(store, source);

    final rules = await _settle(container);

    expect(rules.version, 5);
    expect(source.askedWithTag, 'tag-5');
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
    expect(store.saveAttempts, 1);
  });
}
