/// Reusable color picker row — displays selectable color circles.
library;

import 'package:flutter/material.dart';
import 'package:myloop/app/theme.dart';

/// The 8 player color options available throughout the app.
const playerColors = [
  '#00D4AA', // green
  '#1CB0F6', // blue
  '#FF4B4B', // red
  '#FF9600', // orange
  '#A560E8', // purple
  '#FFC800', // yellow
  '#FF6B81', // pink
  '#2ED8A3', // teal
];

/// A horizontal row of selectable color circles.
///
/// Displays [playerColors] as tappable circles with a check icon
/// on the currently selected index.
class ColorPickerRow extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onColorSelected;
  final double circleSize;

  const ColorPickerRow({
    super.key,
    required this.selectedIndex,
    required this.onColorSelected,
    this.circleSize = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(playerColors.length, (index) {
        final color = Color(
          int.parse(playerColors[index].replaceFirst('#', ''), radix: 16) | 0xFF000000,
        );
        final isSelected = selectedIndex == index;
        return GestureDetector(
          onTap: () => onColorSelected(index),
          child: Container(
            width: circleSize,
            height: circleSize,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? AppColors.darkHard : Colors.transparent,
                width: 3,
              ),
            ),
            child: isSelected
                ? Icon(Icons.check, color: AppColors.white, size: circleSize * 0.5)
                : null,
          ),
        );
      }),
    );
  }
}
