/// Where the app keeps its last-received copy of the game rules (FR1), so it works offline.
library;

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import 'package:myloop/shared/rules/game_rules.dart';
import 'package:myloop/shared/rules/rules_source.dart';

final _log = Logger('RulesStore');

abstract class RulesStore {
  /// The saved rules, or null when none are saved or the saved copy is unreadable.
  Future<SavedRules?> load();

  Future<void> save(SavedRules saved);
}

/// Keeps the rules as JSON in the app documents directory.
class FileRulesStore implements RulesStore {
  static const _fileName = 'game_rules.json';
  static const _tagKey = 'tag';
  static const _rulesKey = 'rules';

  /// Saves run one at a time: app start and login can both refresh the rules, and two
  /// overlapping write-then-rename saves would race on the same temp file.
  Future<void> _lastSave = Future.value();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  @override
  Future<SavedRules?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      if (jsonDecode(await file.readAsString())
          case {_rulesKey: final Map<String, dynamic> rules, _tagKey: final String? tag}) {
        return SavedRules(GameRules.fromJson(rules), tag);
      }
      throw const FormatException('Saved game rules have an unexpected shape');
    } on FormatException catch (e) {
      // A corrupted copy must not block the app: fall back to the built-in rules.
      _log.warning('Saved game rules unreadable; using built-in copy', e);
      return null;
    } on FileSystemException catch (e) {
      _log.warning('Saved game rules could not be read; using built-in copy', e);
      return null;
    }
  }

  @override
  Future<void> save(SavedRules saved) {
    // A failed earlier save was already reported to its own caller; it must not block this one.
    final next = _lastSave.catchError((_) {}).then((_) => _write(saved));
    _lastSave = next;
    return next;
  }

  Future<void> _write(SavedRules saved) async {
    final file = await _file();
    // Write-then-rename so a crash mid-write never leaves a half-written file behind.
    final tmp = File('${file.path}.tmp');
    final json = {_tagKey: saved.tag, _rulesKey: saved.rules.toJson()};
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(file.path);
  }
}
