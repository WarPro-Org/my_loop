/// FR1 — the app always has usable rules: built-in → saved copy → server update.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/rules/game_rules.dart';
import 'package:myloop/shared/rules/game_rules_provider.dart';
import 'package:myloop/shared/rules/rules_source.dart';
import 'package:myloop/shared/rules/rules_store.dart';

GameRules _version(int v) => GameRules.fromJson({...defaultGameRules.toJson(), 'version': v});

class _MemoryStore implements RulesStore {
  _MemoryStore([this.saved]);
  GameRules? saved;
  int saves = 0;
  @override
  Future<GameRules?> load() async => saved;
  @override
  Future<void> save(GameRules rules) async {
    saved = rules;
    saves++;
  }
}

class _FakeSource implements RulesSource {
  _FakeSource({this.serverRules, this.offline = false});
  final GameRules? serverRules;
  final bool offline;
  int? askedWithVersion;
  @override
  Future<GameRules?> fetchIfChanged(int knownVersion) async {
    askedWithVersion = knownVersion;
    if (offline) throw Exception('no internet');
    return serverRules == null || serverRules!.version == knownVersion ? null : serverRules;
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
    expect(store.saved?.version, 6);
    expect(source.askedWithVersion, isNotNull);
  });

  test('up-to-date app asks with its saved version and saves nothing', () async {
    final store = _MemoryStore(_version(5));
    final source = _FakeSource(serverRules: _version(5));
    final container = _container(store, source);

    final rules = await _settle(container);

    expect(rules.version, 5);
    expect(source.askedWithVersion, 5);
    expect(store.saves, 0);
  });
}
