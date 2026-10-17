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
    Object? setting(String path) =>
        path.split(':').fold<Object?>(server, (group, name) => (group as Map<String, dynamic>)[name]);
    // Where each app field lives in appsettings.json. Every field of the built-in copy must be listed, so a field
    // added later can't be missed.
    const serverPaths = {
      'version': 'Version',
      'loopClosureDistanceMeters': 'Loop:ClosureDistanceMeters',
      'minLoopPoints': 'Loop:MinPoints',
      'loopSkipNeighbors': 'Loop:SkipNeighbors',
      'gpsAccuracyThresholdMeters': 'Gps:AccuracyThresholdMeters',
      'minLoopAreaSquareMeters': 'Loop:MinAreaSquareMeters',
      'autoEndVehicleSpeedMetersPerSecond': 'AutoEnd:VehicleSpeedMetersPerSecond',
      'autoEndVehicleSeconds': 'AutoEnd:VehicleSeconds',
      'autoEndStillRadiusMeters': 'AutoEnd:StillRadiusMeters',
      'autoEndStillSeconds': 'AutoEnd:StillSeconds',
      'autoEndStillMaxWalkedMeters': 'AutoEnd:StillMaxWalkedMeters',
    };
    final builtIn = defaultGameRules.toJson();

    expect(builtIn.keys.toSet(), serverPaths.keys.toSet());
    for (final MapEntry(key: field, value: path) in serverPaths.entries) {
      expect(builtIn[field], setting(path), reason: '$field must match GameRules:$path');
    }
  });

  test('the app never knows anti-cheat numbers', () {
    // The auto-end vehicle speed is a walk rule above both anti-cheat speeds (FR2), the only speed the app may know.
    final keys = defaultGameRules.toJson().keys
        .where((key) => key != 'autoEndVehicleSpeedMetersPerSecond')
        .join(',')
        .toLowerCase();

    expect(keys, isNot(contains('speed')));
    expect(keys, isNot(contains('violation')));
    expect(keys, isNot(contains('drift')));
  });
}
