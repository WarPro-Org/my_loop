/// Tests for parsing the claim-preview response (issue #21).
///
/// The app must read the server's authoritative `loopCount` and tolerate a
/// response without it (older server) by defaulting to 0 rather than crashing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/services/api_service.dart';

void main() {
  group('PreviewResult.fromJson', () {
    test('reads boundaries and the authoritative loopCount', () {
      final result = PreviewResult.fromJson({
        'boundaries': [
          [
            [1.0, 2.0],
            [3.0, 4.0],
          ],
        ],
        'loopCount': 2,
      });

      expect(result.loopCount, 2);
      expect(result.boundaries, hasLength(1));
      expect(result.boundaries.first.first, [1.0, 2.0]);
    });

    test('defaults loopCount to 0 when the field is absent', () {
      final result = PreviewResult.fromJson({'boundaries': []});
      expect(result.loopCount, 0);
      expect(result.boundaries, isEmpty);
    });

    test('coerces integer-typed coordinates to double', () {
      final result = PreviewResult.fromJson({
        'boundaries': [
          [
            [1, 2],
          ],
        ],
        'loopCount': 1,
      });
      expect(result.boundaries.first.first, [1.0, 2.0]);
      expect(result.boundaries.first.first.first, isA<double>());
    });

    test('tolerates a missing boundaries field', () {
      final result = PreviewResult.fromJson({'loopCount': 3});
      expect(result.boundaries, isEmpty);
      expect(result.loopCount, 3);
    });
  });
}
