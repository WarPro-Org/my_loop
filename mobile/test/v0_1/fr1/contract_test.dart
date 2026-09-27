/// FR1: the app reads, field for field, the same sample the server's tests check
/// (tests/contracts/client_rules.json), so a field changed on either side fails a test.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/rules/game_rules.dart';

/// `flutter test` runs from mobile/; the sample lives at the repo root.
const _samplePath = '../tests/contracts/client_rules.json';

void main() {
  final sample = jsonDecode(File(_samplePath).readAsStringSync()) as Map<String, dynamic>;

  test('the app reads every field of the server sample', () {
    final rules = GameRules.fromJson(sample);

    expect(rules.version, sample['version']);
    expect(rules.loopClosureDistanceMeters, sample['loopClosureDistanceMeters']);
    expect(rules.minLoopPoints, sample['minLoopPoints']);
    expect(rules.loopSkipNeighbors, sample['loopSkipNeighbors']);
    expect(rules.gpsAccuracyThresholdMeters, sample['gpsAccuracyThresholdMeters']);
  });

  test('the app knows exactly the fields the server sends', () {
    expect(GameRules.fromJson(sample).toJson().keys.toSet(), sample.keys.toSet());
  });
}
