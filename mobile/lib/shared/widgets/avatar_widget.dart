import 'package:flutter/material.dart';

// List of avatar emojis players can pick from
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

// Displays the player's avatar emoji in a colored circle
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

  @override
  Widget build(BuildContext context) {
    // Parse hex color string like "#FF5733"
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
