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

  group('rejects a response with a null or wrong-type field instead of half-applying it', () {
    final cases = <String, Object?>{
      'a null whole number': null,
      'a whole number sent as text': '20',
      'a whole number sent with a fraction': 20.5,
    };
    for (final MapEntry(key: name, value: value) in cases.entries) {
      test(name, () {
        final json = {...defaultGameRules.toJson(), 'minLoopPoints': value};

        expect(() => GameRules.fromJson(json), throwsFormatException);
      });
    }

    test('a null decimal', () {
      final json = {...defaultGameRules.toJson(), 'gpsAccuracyThresholdMeters': null};

      expect(() => GameRules.fromJson(json), throwsFormatException);
    });

    test('a decimal sent as text', () {
      final json = {...defaultGameRules.toJson(), 'gpsAccuracyThresholdMeters': '50'};

      expect(() => GameRules.fromJson(json), throwsFormatException);
    });
  });

  test('accepts a response with a field it does not know (a newer server)', () {
    final json = {...defaultGameRules.toJson(), 'fieldFromANewerServer': 7};

    expect(GameRules.fromJson(json).toJson(), defaultGameRules.toJson(),
        reason: 'old phones must keep working when the server adds a field');
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
