/// FR1 — the saved copy of the rules survives restarts and overlapping saves.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/rules/game_rules.dart';
import 'package:myloop/shared/rules/rules_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

GameRules _version(int v) => GameRules.fromJson({...defaultGameRules.toJson(), 'version': v});

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fr1_rules_store');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('nothing saved yet → null (the app then uses the built-in copy)', () async {
    expect(await FileRulesStore().load(), isNull);
  });

  test('a saved copy is read back by a fresh store (survives an app restart)', () async {
    await FileRulesStore().save(_version(4));

    final reopened = await FileRulesStore().load();

    expect(reopened?.toJson(), _version(4).toJson());
  });

  test('a corrupted saved copy is ignored instead of crashing', () async {
    await File('${tempDir.path}/game_rules.json').writeAsString('{not json');

    expect(await FileRulesStore().load(), isNull);
  });

  test('overlapping saves never fail and the last one wins on disk', () async {
    for (var round = 0; round < 25; round++) {
      final store = FileRulesStore();

      await Future.wait([
        store.save(_version(2)),
        store.save(_version(3)),
        store.save(_version(4)),
      ]);

      final onDisk = await FileRulesStore().load();
      expect(onDisk?.version, 4, reason: 'round $round');
      expect(File('${tempDir.path}/game_rules.json.tmp').existsSync(), isFalse);
    }
  });
}
