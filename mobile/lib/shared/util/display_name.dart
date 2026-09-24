/// Display-name validation shared by onboarding, local signup and profile rename.
library;

import 'package:myloop/shared/constants/app_constants.dart';

/// Latin script only (#189): ASCII, Latin-1 letters (minus × U+00D7 and ÷ U+00F7),
/// Latin Extended-A/B (minus the punctuation-like click letters U+01C0–U+01C3) and Latin
/// Extended Additional, plus digits, space, `-`, `_`, `'`
/// and the iOS smart apostrophe `’` (U+2019), which the API folds to `'` before storing.
///
/// Mirrors MyDisplayNameRegex in api/MyLoop.Api/Services/ValidationService.cs. The API also
/// NFC-normalises, so it accepts decomposed input this pattern rejects — the client is only
/// ever stricter, never looser, than the server.
final displayNamePattern = RegExp(
  r"^[A-Za-z0-9À-ÖØ-öø-ƿǄ-ɏḀ-ỿ \-_'’]+$",
);

const displayNameEmptyError = 'Name cannot be empty';
const displayNameTooShortError =
    'Name must be at least ${AppConstants.minDisplayNameLength} characters';
const displayNameTooLongError =
    'Name must be ${AppConstants.maxDisplayNameLength} characters or less';
const displayNameCharactersError = 'Only letters, numbers, spaces, hyphens and apostrophes allowed';
const displayNameOfflineError = "You're offline — connect to change your name";
const displayNameSaveFailedError = "Couldn't save your name — try again";

const _smartApostrophe = '\u2019';

/// The form the API stores: trimmed, with the iOS smart apostrophe folded to `'`. Apply before
/// an optimistic local update so the screen shows what the server persists. (The API also
/// NFC-normalises; iOS and Android keyboards already emit composed text, so that is omitted.)
String canonicalDisplayName(String name) => name.trim().replaceAll(_smartApostrophe, "'");

/// Returns an error message for [name], or null when it is valid. Trims first, matching
/// what the API stores.
String? validateDisplayName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return displayNameEmptyError;
  if (trimmed.length < AppConstants.minDisplayNameLength) return displayNameTooShortError;
  if (trimmed.length > AppConstants.maxDisplayNameLength) return displayNameTooLongError;
  if (!displayNamePattern.hasMatch(trimmed)) return displayNameCharactersError;
  return null;
}
