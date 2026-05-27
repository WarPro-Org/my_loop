/// Avatar widget and emoji definitions for player identity display.
///
/// Provides the [AvatarWidget] which renders a player's chosen emoji
/// inside a colored circle, plus the [avatarEmojis] constant list that
/// defines all selectable avatar characters.
library;

import 'package:flutter/material.dart';

/// The ordered list of emoji characters available as player avatars.
///
/// Index position maps to the [AppUser.avatarId] stored in the backend.
const avatarEmojis = [
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

/// Displays a player's avatar emoji inside a tinted circular badge.
///
/// Takes an [avatarId] (index into [avatarEmojis]), a hex [color] string
/// (e.g., `'#00D4AA'`), and optional [size]. The circle uses the player's
/// color at 20% opacity as the background with a solid-color border.
class AvatarWidget extends StatelessWidget {
  final int avatarId;
  final String color;
  final double size;

  const AvatarWidget({
    super.key,
    required this.avatarId,
    required this.color,
    this.size = 48,
  });

  /// Builds the circular avatar badge.
  @override
  Widget build(BuildContext context) {
    // Parse hex color string like "#FF5733" into a Flutter Color
    final bgColor = Color(
      int.parse(color.replaceFirst('#', ''), radix: 16) | 0xFF000000,
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: bgColor, width: 3),
      ),
      child: Center(
        child: Text(
          avatarEmojis[avatarId.clamp(0, avatarEmojis.length - 1)],
          style: TextStyle(fontSize: size * 0.5),
        ),
      ),
    );
  }
}
