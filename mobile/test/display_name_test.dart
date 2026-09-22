import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/util/display_name.dart';

/// DR-002a / #189: mirrors DisplayNameValidationTests in the API so the two validators
/// accept the same Latin-only set.
void main() {
  group('validateDisplayName accepts Latin-script names', () {
    for (final name in [
      'Ravi', 'José', 'Zoë', 'François', 'Müller', 'Straße', 'Łukasz', 'Søren Ødegård',
      'Ștefan', 'Çağrı Işık', 'Nguyễn', 'Jean-Luc_2', "O'Brien", 'O’Brien',
      '  José  ', // trimmed, like the API
    ]) {
      test(name, () => expect(validateDisplayName(name), isNull));
    }
  });

  group('validateDisplayName rejects other scripts and malformed names', () {
    final cases = {
      'Аdmin': displayNameCharactersError, // Cyrillic А look-alike
      'Αλέξης': displayNameCharactersError,
      'रवि': displayNameCharactersError,
      '陈伟': displayNameCharactersError,
      'Ali×2': displayNameCharactersError,
      'Ann÷': displayNameCharactersError,
      'Zé́': displayNameCharactersError,
      'Bob😀': displayNameCharactersError,
      'Bob.': displayNameCharactersError,
      'A': displayNameTooShortError,
      'Abcdefghijklmnopqrstu': displayNameTooLongError,
      '   ': displayNameEmptyError,
    };
    cases.forEach((name, error) {
      test(name, () => expect(validateDisplayName(name), error));
    });
  });

  test('canonicalDisplayName folds the iOS apostrophe and trims, like the API', () {
    expect(canonicalDisplayName('  O’Brien '), "O'Brien");
    expect(canonicalDisplayName('José'), 'José');
  });
}
