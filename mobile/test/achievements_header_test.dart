import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/models/achievements.dart';

void main() {
  group('Achievements data integrity', () {
    test('all achievements have valid fields', () {
      for (final a in achievements) {
        expect(a.id.isNotEmpty, true, reason: '${a.name} should have non-empty id');
        expect(a.name.isNotEmpty, true);
        expect(a.description.isNotEmpty, true);
        expect(a.emoji.isNotEmpty, true);
        expect(a.tier1, greaterThan(0));
        expect(a.tier2, greaterThanOrEqualTo(a.tier1));
        expect(a.tier3, greaterThanOrEqualTo(a.tier2));
      }
    });

    test('no broken unicode in achievement names or descriptions', () {
      for (final a in achievements) {
        expect(a.name.contains('\u00e2'), false,
            reason: 'Achievement "${a.name}" contains broken UTF-8');
        expect(a.description.contains('\u00e2'), false,
            reason: 'Description "${a.description}" contains broken UTF-8');
        expect(a.emoji.contains('\u00e2'), false,
            reason: 'Emoji for "${a.name}" contains broken UTF-8');
      }
    });

    test('getStars returns correct values', () {
      final a = achievements.first;
      expect(a.getStars(0), 0);
      expect(a.getStars(a.tier1), 1);
      expect(a.getStars(a.tier2), 2);
      expect(a.getStars(a.tier3), 3);
      expect(a.getStars(a.tier3 + 100), 3); // capped at 3
    });
  });
}
