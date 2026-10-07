/// FR1 — the saved copy of the rules survives restarts and overlapping saves.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/rules/game_rules.dart';
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

SavedRules _version(int v) =>
    SavedRules(GameRules.fromJson({...defaultGameRules.toJson(), 'version': v}), 'tag-$v');

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

    expect(reopened?.rules.toJson(), _version(4).rules.toJson());
    expect(reopened?.tag, 'tag-4');
  });

  test('a corrupted saved copy is ignored instead of crashing', () async {
    await File('${tempDir.path}/game_rules.json').writeAsString('{not json');

    expect(await FileRulesStore().load(), isNull);
  });

  test('a saved copy with an unexpected shape is ignored instead of crashing', () async {
    await File('${tempDir.path}/game_rules.json').writeAsString('{"rules": 42}');

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
      expect(onDisk?.rules.version, 4, reason: 'round $round');
      expect(File('${tempDir.path}/game_rules.json.tmp').existsSync(), isFalse);
    }
  });

  test('RulesStore is the only code that touches the saved rules file', () {
    // One owner per file (LIFE-9): another writer could race the store's write-then-rename save.
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final namingTheFile = sources
        .where((file) => file.readAsStringSync().contains('game_rules.json'))
        .map((file) => file.path.replaceAll('\\', '/'))
        .toList();
    final buildingTheStore = sources
        .where((file) => file.readAsStringSync().contains('FileRulesStore('))
        .map((file) => file.path.replaceAll('\\', '/'))
        .toList();

    expect(namingTheFile, ['lib/shared/rules/rules_store.dart']);
    expect(buildingTheStore, unorderedEquals(['lib/shared/rules/rules_store.dart', 'lib/shared/rules/game_rules_provider.dart']),
        reason: 'only the provider creates the store, so the app has a single instance');
  });
}
