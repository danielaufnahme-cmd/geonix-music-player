import 'package:flutter/material.dart';

import '../theme.dart';
import 'cover_image.dart';

/// Playlist artwork: a 2×2 mosaic of the first four album covers.
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({super.key, required this.trackIds, this.size = 176, this.radius = 16, this.discover = false});

  final List<String> trackIds;
  final double size;
  final double radius;
  final bool discover;

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    Widget child;
    if (trackIds.length >= 4) {
      final half = size / 2;
      child = Column(children: [
        Row(children: [
          CoverImage(videoId: trackIds[0], size: half, radius: 0),
          CoverImage(videoId: trackIds[1], size: half, radius: 0),
        ]),
        Row(children: [
          CoverImage(videoId: trackIds[2], size: half, radius: 0),
          CoverImage(videoId: trackIds[3], size: half, radius: 0),
        ]),
      ]);
    } else if (trackIds.isNotEmpty) {
      child = CoverImage(videoId: trackIds.first, size: size, radius: 0);
    } else {
      child = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [gx.accent.withValues(alpha: 0.85), gx.accent.withValues(alpha: 0.25), gx.surfaceHigh],
          ),
        ),
        child: Center(
          child: Icon(discover ? Icons.auto_awesome_rounded : Icons.queue_music_rounded,
              size: size * 0.36, color: Colors.white.withValues(alpha: 0.9)),
        ),
      );
    }
    final mosaic = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: child),
    );
    if (!discover || trackIds.isEmpty) return mosaic;
    // The Discover Mix gets a tinted overlay with a sparkle so it stands out.
    return Stack(children: [
      mosaic,
      Positioned.fill(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [gx.accent.withValues(alpha: 0.75), Colors.transparent],
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: size * 0.08,
        bottom: size * 0.08,
        child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * 0.18),
      ),
    ]);
  }
}
