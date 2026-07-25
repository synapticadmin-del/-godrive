import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Skeleton (shimmer-like placeholder) loading box. Use [SkeletonBox] for
/// rectangular placeholders and [SkeletonList] to build a list of items.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? AppTokens.darkSurface : AppTokens.lightSurface;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A full skeleton list with [count] rows, each containing a leading circle
/// and two text lines — mimics a typical list/card layout while loading.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.count = 5,
    this.itemHeight = 72,
  });

  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const SkeletonBox(width: 48, height: 48, radius: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 160, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}