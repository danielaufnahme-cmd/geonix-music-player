import 'package:flutter/material.dart';

import '../api/client.dart';
import '../theme.dart';

/// Song cover served by the backend, with a fade-in and a soft placeholder.
class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.videoId, this.size, this.radius = 10, this.circle = false});

  final String videoId;
  final double? size;
  final double radius;
  final bool circle;

  static String urlFor(String videoId) => '$kApiBase/api/tracks/$videoId/cover';

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gx.surfaceHigh, gx.accent.withValues(alpha: 0.25)],
        ),
      ),
      child: Center(child: Icon(Icons.music_note_rounded, color: gx.muted, size: (size ?? 48) * 0.4)),
    );
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final image = videoId.isEmpty
        ? placeholder
        : Image.network(
            urlFor(videoId),
            fit: BoxFit.cover,
            cacheWidth: size == null ? null : (size! * dpr).round(),
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, sync) => sync
                ? child
                : AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                    child: child,
                  ),
            errorBuilder: (context, error, stack) => placeholder,
          );
    final framed = SizedBox(
      width: size,
      height: size,
      child: Stack(fit: StackFit.expand, children: [placeholder, image]),
    );
    return circle
        ? ClipOval(child: framed)
        : ClipRRect(borderRadius: BorderRadius.circular(radius), child: framed);
  }
}
