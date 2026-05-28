/// Shimmer loading placeholder widget.
///
/// Displays animated gradient rectangles as content placeholders
/// while data is loading. Used across all main screens.
library;

import 'package:flutter/material.dart';
import 'package:myloop/app/theme.dart';

/// A shimmer-animated placeholder block.
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 12,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
              end: Alignment(-1.0 + 2.0 * _controller.value + 1.0, 0),
              colors: const [
                AppColors.greyLight,
                AppColors.snow,
                AppColors.greyLight,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A pre-built shimmer placeholder for a list of cards.
class ShimmerList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final EdgeInsets padding;

  const ShimmerList({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 72,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: List.generate(itemCount, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ShimmerBox(height: itemHeight),
        )),
      ),
    );
  }
}

/// Shimmer placeholder for a stats grid (like profile/home).
class ShimmerGrid extends StatelessWidget {
  const ShimmerGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const ShimmerBox(height: 48, borderRadius: 8),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: ShimmerBox(height: 100)),
              const SizedBox(width: 12),
              const Expanded(child: ShimmerBox(height: 100)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: ShimmerBox(height: 100)),
              const SizedBox(width: 12),
              const Expanded(child: ShimmerBox(height: 100)),
            ],
          ),
        ],
      ),
    );
  }
}
