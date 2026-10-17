/// Where the app keeps its last-received copy of the game rules (FR1), so it works offline.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  FileRulesStore({@visibleForTesting Future<void> Function(File tmp, String path)? replace})
      : _replace = replace ?? _rename;

  /// Swaps the fully written temp file in for the saved copy; a test can make it fail to act as
  /// a crash between writing and swapping.
  final Future<void> Function(File tmp, String path) _replace;

  static Future<void> _rename(File tmp, String path) => tmp.rename(path);

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
        return _upgraded(rules, tag);
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

  /// A copy saved before rules version 2 has none of [fieldsAddedInVersion2]. Its server values are kept and only
  /// the missing new fields come from the built-in copy (O10). Its tag is dropped: with the server deployed first,
  /// the old app may have saved the new server's tag while ignoring the new fields, so keeping the tag would earn
  /// a 304 and the phone would never get the server's values for them. With no tag the next refresh is a full reply.
  static SavedRules _upgraded(Map<String, dynamic> rules, String? tag) {
    final missing = fieldsAddedInVersion2.where((key) => !rules.containsKey(key)).toList();
    if (missing.isEmpty) return SavedRules(GameRules.fromJson(rules), tag);

    _log.info('Saved game rules predate version 2; filling ${missing.join(', ')} from the built-in copy');
    final builtIn = defaultGameRules.toJson();
    final filled = {...rules, for (final key in missing) key: builtIn[key]};
    return SavedRules(GameRules.fromJson(filled), null);
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
    await _replace(tmp, file.path);
  }
}
