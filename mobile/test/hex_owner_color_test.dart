/// Regression tests for the owner-colour swatch on the hex detail sheet (#112).
///
/// `HexTerritoryManager` keeps freshly captured / step-claimed cells in the same
/// keyed store the map taps against, and those placeholders carry no owner
/// colour yet. The sheet used to parse that colour with `int.parse`, so tapping
/// a hex you had just claimed threw a FormatException. These lock in that the
/// parse tolerates the placeholder instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/features/journey/hex_territory_manager.dart';
import 'package:myloop/shared/services/api_service.dart';

const _boundary = [
  [37.4220, -122.0841],
  [37.4221, -122.0841],
  [37.4221, -122.0840],
  [37.4220, -122.0841],
];

void main() {
  group('AppColors.fromHex', () {
    test('parses a #RRGGBB colour and forces full opacity', () {
      expect(AppColors.fromHex('#FF00AA'), const Color(0xFFFF00AA));
    });

    test('parses without the leading hash', () {
      expect(AppColors.fromHex('FF00AA'), const Color(0xFFFF00AA));
    });

    test('falls back instead of throwing on an empty string', () {
      expect(AppColors.fromHex(''), AppColors.hexUnknownOwner);
    });

    test('falls back instead of throwing on a bare hash', () {
      expect(AppColors.fromHex('#'), AppColors.hexUnknownOwner);
    });

    test('falls back instead of throwing on a non-hex string', () {
      expect(AppColors.fromHex('not-a-colour'), AppColors.hexUnknownOwner);
    });

    test('honours an explicit fallback', () {
      expect(AppColors.fromHex('', fallback: AppColors.primary), AppColors.primary);
    });
  });

  // The seam that actually broke: the colour the sheet parses comes straight off
  // a cell in the manager's store, and these two paths put colourless cells there.
  group('cells the map can tap never crash the swatch', () {
    const userId = 'user-1';

    HexTerritoryManager manager() =>
        HexTerritoryManager(api: ApiService(), userId: userId);

    test('a loop-captured placeholder resolves to the fallback swatch', () {
      final m = manager()..addCapturedHexes([_boundary]);
      final cell = m.allCells.single;

      expect(cell.ownerId, userId, reason: 'the sheet treats this as an own hex');
      expect(AppColors.fromHex(cell.ownerColor), AppColors.hexUnknownOwner);
    });

    test('a step-claimed cell not previously in the store resolves too', () {
      final m = manager()..integrateStepClaim(_boundary, 123456789, false);
      final cell = m.allCells.single;

      expect(cell.ownerId, userId);
      expect(AppColors.fromHex(cell.ownerColor), AppColors.hexUnknownOwner);
    });
  });
}
