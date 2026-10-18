import 'package:flutter/material.dart';

import '../theme.dart';

/// Animated shimmer over skeleton placeholders (used instead of spinners).
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value * 2 - 0.5;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [gx.surfaceHigh, gx.text.withValues(alpha: 0.12), gx.surfaceHigh],
            stops: [(t - 0.3).clamp(0.0, 1.0), t.clamp(0.0, 1.0), (t + 0.3).clamp(0.0, 1.0)],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8, this.circle = false});
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.gx.surfaceHigh,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(radius),
        ),
      );
}

/// Placeholder rows shaped like song rows.
class SkeletonTrackList extends StatelessWidget {
  const SkeletonTrackList({super.key, this.count = 8});
  final int count;

  @override
  Widget build(BuildContext context) => Shimmer(
        child: Column(
          children: [
            for (var i = 0; i < count; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  const SkeletonBox(width: 44, height: 44, radius: 8),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SkeletonBox(width: 160.0 + (i * 37) % 120, height: 13),
                      const SizedBox(height: 8),
                      SkeletonBox(width: 90.0 + (i * 23) % 80, height: 11),
                    ]),
                  ),
                  const SkeletonBox(width: 36, height: 11),
                ]),
              ),
          ],
        ),
      );
}

/// Placeholder row of cover cards.
class SkeletonCardRow extends StatelessWidget {
  const SkeletonCardRow({super.key, this.count = 6, this.cardWidth = 176});
  final int count;
  final double cardWidth;

  @override
  Widget build(BuildContext context) => Shimmer(
        child: SizedBox(
          height: cardWidth + 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 18),
            itemBuilder: (_, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SkeletonBox(width: cardWidth, height: cardWidth, radius: 16),
              const SizedBox(height: 12),
              SkeletonBox(width: cardWidth * 0.75, height: 13),
              const SizedBox(height: 8),
              SkeletonBox(width: cardWidth * 0.5, height: 11),
            ]),
          ),
        ),
      );
}
