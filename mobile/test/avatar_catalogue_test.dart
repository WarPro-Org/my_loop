import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/widgets/avatar_widget.dart';
import 'package:myloop/shared/widgets/color_picker_row.dart';

/// DR-001 / #188: the server stores an avatar as its *position* in [avatarEmojis]. Reordering
/// or deleting an entry silently reassigns every stored id (players who picked the fox open
/// the app as a shark). The server-side drift test only checks the count, so the order is
/// pinned here. Appending a new avatar is allowed: add it to the end of [frozenAvatars] and
/// bump GameConstants.AvatarCount in the API in the same change.
void main() {
  const frozenAvatars = [
    '🦊', // 0 - fox
    '🐸', // 1 - frog
    '🦉', // 2 - owl
    '🐯', // 3 - tiger
    '🐼', // 4 - panda
    '🦁', // 5 - lion
    '🐨', // 6 - koala
    '🐙', // 7 - octopus
    '🦄', // 8 - unicorn
    '🐲', // 9 - dragon
    '🦈', // 10 - shark
    '🦅', // 11 - eagle
  ];

  test('existing avatar ids keep their emoji (append-only catalogue)', () {
    expect(avatarEmojis.length, greaterThanOrEqualTo(frozenAvatars.length),
        reason: 'An avatar was deleted — stored ids past it would shift.');
    for (var id = 0; id < frozenAvatars.length; id++) {
      expect(avatarEmojis[id], frozenAvatars[id],
          reason: 'Avatar id $id changed — stored ids are positional and permanent.');
    }
  });

  test('avatar catalogue has no duplicates', () {
    expect(avatarEmojis.toSet().length, avatarEmojis.length);
  });

  test('player colours are uppercase #RRGGBB (server matches them exactly)', () {
    for (final color in playerColors) {
      expect(color, matches(RegExp(r'^#[0-9A-F]{6}$')));
    }
    expect(playerColors.toSet().length, playerColors.length);
  });
}
