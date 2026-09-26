/// FR1 — the rules model and the built-in copy.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/rules/game_rules.dart';

void main() {
  test('reads the server response and writes it back unchanged', () {
    final json = defaultGameRules.toJson();

    final rules = GameRules.fromJson(json);

    expect(rules.toJson(), json);
  });

  test('accepts whole numbers for decimal fields (server sends 50, not 50.0)', () {
    final json = {...defaultGameRules.toJson(), 'loopClosureDistanceMeters': 50};

    expect(GameRules.fromJson(json).loopClosureDistanceMeters, 50.0);
  });

  test('rejects a response with a missing field instead of half-applying it', () {
    final json = defaultGameRules.toJson()..remove('minLoopPoints');

    expect(() => GameRules.fromJson(json), throwsFormatException);
  });

  test('built-in copy matches the server rules in appsettings.json', () {
    // Test runs from mobile/, so the API settings are one folder up.
    final settings = jsonDecode(
      File('../api/MyLoop.Api/appsettings.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final server = settings['GameRules'] as Map<String, dynamic>;
    final loop = server['Loop'] as Map<String, dynamic>;

    expect(defaultGameRules.version, server['Version']);
    expect(defaultGameRules.loopClosureDistanceMeters, loop['ClosureDistanceMeters']);
    expect(defaultGameRules.minLoopPoints, loop['MinPoints']);
    expect(defaultGameRules.loopSkipNeighbors, loop['SkipNeighbors']);
    expect(defaultGameRules.gpsAccuracyThresholdMeters,
        (server['Gps'] as Map)['AccuracyThresholdMeters']);
  });

  test('the app never knows anti-cheat numbers', () {
    final keys = defaultGameRules.toJson().keys.join(',').toLowerCase();

    expect(keys, isNot(contains('speed')));
    expect(keys, isNot(contains('violation')));
    expect(keys, isNot(contains('drift')));
  });
}
