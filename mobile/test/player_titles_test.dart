import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/models/player_titles.dart';

void main() {
  group('Player Titles', () {
    test('0 hexes returns Fresh Feet', () {
      final title = getTitleForHexes(0);
      expect(title.label, 'Fresh Feet');
    });

    test('10 hexes returns Ground Breaker', () {
      final title = getTitleForHexes(10);
      expect(title.label, 'Ground Breaker');
    });

    test('50 hexes returns Path Finder', () {
      final title = getTitleForHexes(50);
      expect(title.label, 'Path Finder');
    });

    test('200 hexes returns Hex Hunter', () {
      final title = getTitleForHexes(200);
      expect(title.label, 'Hex Hunter');
    });

    test('500 hexes returns Trail Blazer', () {
      final title = getTitleForHexes(500);
      expect(title.label, 'Trail Blazer');
    });

    test('1000 hexes returns Grid Dominator', () {
      final title = getTitleForHexes(1000);
      expect(title.label, 'Grid Dominator');
    });

    test('10000 hexes returns Hex Overlord', () {
      final title = getTitleForHexes(10000);
      expect(title.label, 'Hex Overlord');
    });

    test('title has non-empty emoji', () {
      final title = getTitleForHexes(500);
      expect(title.emoji.isNotEmpty, true);
    });
  });
}
