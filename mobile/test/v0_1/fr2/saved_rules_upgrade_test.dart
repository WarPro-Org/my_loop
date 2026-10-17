/// FR2 (O10, design "Saved rules after the app update", lifecycle reader R6): a rules copy saved by an app from
/// before rules version 2 keeps its server values, gets only the new fields from the built-in copy, and loses its
/// tag, so the next refresh is a full reply carrying the server's values for the new fields.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/rules/game_rules.dart';
import 'package:myloop/shared/rules/game_rules_provider.dart';
import 'package:myloop/shared/rules/rules_source.dart';
import 'package:myloop/shared/rules/rules_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// The server: answers 304 (null) to its own tag, else its rules; records the tag each request carried.
class _Server implements RulesSource {
  _Server(this.rules);
  final SavedRules rules;
  final askedWithTags = <String?>[];
  @override
  Future<SavedRules?> fetchIfChanged(String? knownTag) async {
    askedWithTags.add(knownTag);
    return knownTag == rules.tag ? null : rules;
  }
}

const _serverTag = '2-abcdef0123456789';

/// Values an old app saved from the server: FR1's fields only, each different from the built-in copy.
const _oldServerValues = <String, Object>{
  'version': 2,
  'loopClosureDistanceMeters': 45.5,
  'minLoopPoints': 22,
  'loopSkipNeighbors': 9,
  'gpsAccuracyThresholdMeters': 40.5,
};

/// The server's version 2 rules, with new-field values that differ from the built-in copy.
final _serverRules = SavedRules(
  GameRules.fromJson({
    ..._oldServerValues,
    'minLoopAreaSquareMeters': 6000.5,
    'autoEndVehicleSpeedMetersPerSecond': 10.5,
    'autoEndVehicleSeconds': 200,
    'autoEndStillRadiusMeters': 80.5,
    'autoEndStillSeconds': 700,
    'autoEndStillMaxWalkedMeters': 300.5,
  }),
  _serverTag,
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fr2_saved_rules_upgrade');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Writes the file exactly as the FR1 app's `FileRulesStore` did: `{"tag": …, "rules": {…}}`.
  Future<void> savedByOldApp(Map<String, Object> rules, String? tag) =>
      File('${tempDir.path}/game_rules.json').writeAsString(jsonEncode({'tag': tag, 'rules': rules}));

  test('an old saved copy keeps its server values and gets only the new fields from the built-in copy', () async {
    await savedByOldApp(_oldServerValues, _serverTag);

    final loaded = (await FileRulesStore().load())?.rules.toJson() ?? {};

    for (final MapEntry(:key, :value) in _oldServerValues.entries) {
      expect(loaded[key], value, reason: '$key must keep the server value');
    }
    final builtIn = defaultGameRules.toJson();
    for (final key in fieldsAddedInVersion2) {
      expect(loaded[key], builtIn[key], reason: '$key must come from the built-in copy');
    }
  });

  test('an old saved copy loses its tag', () async {
    await savedByOldApp(_oldServerValues, _serverTag);

    final loaded = await FileRulesStore().load();

    expect(loaded, isNotNull, reason: 'positive control: the old copy loads');
    expect(loaded?.tag, isNull);
  });

  test('positive control: a saved version 2 copy keeps its tag and every saved value', () async {
    await FileRulesStore().save(_serverRules);

    final loaded = await FileRulesStore().load();

    expect(loaded?.tag, _serverTag);
    expect(loaded?.rules.toJson(), _serverRules.rules.toJson());
  });

  test('an old saved copy missing an FR1 field is still rejected', () async {
    await savedByOldApp({..._oldServerValues}..remove('minLoopPoints'), _serverTag);

    expect(await FileRulesStore().load(), isNull);
  });

  test('old app saved the new server tag, app updated: the next refresh is a full reply with the server values',
      () async {
    await savedByOldApp(_oldServerValues, _serverTag);
    final server = _Server(_serverRules);
    final container = ProviderContainer(overrides: [
      rulesStoreProvider.overrideWithValue(FileRulesStore()),
      rulesSourceProvider.overrideWithValue(server),
    ]);
    addTearDown(container.dispose);

    container.read(gameRulesProvider);
    await container.read(gameRulesProvider.notifier).refresh();

    // Later requests carry the tag of the full reply, which is the same string; only the first one tells.
    expect(server.askedWithTags.first, isNull, reason: 'the old tag would earn a 304 and keep the built-in values');
    expect(container.read(gameRulesProvider).toJson(), _serverRules.rules.toJson());
    final saved = await FileRulesStore().load();
    expect(saved?.tag, _serverTag, reason: 'the full reply is saved with its tag');
    expect(saved?.rules.toJson(), _serverRules.rules.toJson());
  });
}
