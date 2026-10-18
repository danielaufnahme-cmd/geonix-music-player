import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/now_playing_screen.dart';
import '../state/player_controller.dart';
import '../theme.dart';
import 'cover_image.dart';
import 'player_controls.dart';
import 'seek_bar.dart';
import 'waves.dart';

class QueueOpen extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
}

/// Whether the "Up next" side panel is shown.
final queueOpenProvider = NotifierProvider<QueueOpen, bool>(QueueOpen.new);

/// Always-visible bottom bar: frosted glass over the content behind it.
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final track = ref.watch(currentTrackProvider);
    final volume = ref.watch(playerProvider.select((s) => s.volume));
    final queueOpen = ref.watch(queueOpenProvider);
    final wide = MediaQuery.sizeOf(context).width > 1180;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          height: kPlayerBarHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.alphaBlend(gx.accent.withValues(alpha: 0.10), gx.surface.withValues(alpha: 0.78)),
                gx.surface.withValues(alpha: 0.72),
              ],
            ),
            border: Border.all(color: gx.outline),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Stack(
            children: [
              // A faint wave drifting inside the glass while music plays.
              Positioned.fill(
                child: IgnorePointer(
                  child: WaveBackground(
                    accent: gx.accent,
                    deep: ref.watch(currentPaletteProvider).deep,
                    aurora: false,
                    intensity: 0.45,
                    heightFactor: 0.75,
                    layers: 2,
                    reducedRate: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    // Now playing
                    Expanded(
                      flex: 3,
                      child: track == null
                          ? Text('Nothing playing', style: text.bodyMedium?.copyWith(color: gx.muted))
                          : MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () => openNowPlaying(context),
                                child: Row(
                                  children: [
                                    Hero(
                                      tag: 'now-playing-cover',
                                      child: CoverImage(videoId: track.videoId, size: 58, radius: 12),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 300),
                                        transitionBuilder: (child, a) => FadeTransition(
                                          opacity: a,
                                          child: SlideTransition(
                                            position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a),
                                            child: child,
                                          ),
                                        ),
                                        child: Column(
                                          key: ValueKey(track.videoId),
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              track.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              track.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: text.bodySmall?.copyWith(color: gx.muted),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    // Controls
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const PlayerControls(),
                          SizedBox(height: 26, child: const SeekBar()),
                        ],
                      ),
                    ),
                    // Extras
                    Expanded(
                      flex: 3,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'Up next',
                            onPressed: () => ref.read(queueOpenProvider.notifier).toggle(),
                            icon: Icon(Icons.queue_music_rounded, color: queueOpen ? gx.accent : gx.muted),
                          ),
                          IconButton(
                            tooltip: volume == 0 ? 'Unmute' : 'Mute',
                            onPressed: () => ref.read(playerProvider.notifier).setVolume(volume == 0 ? 80 : 0),
                            icon: Icon(
                              volume == 0
                                  ? Icons.volume_off_rounded
                                  : (volume < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                              color: gx.muted,
                            ),
                          ),
                          if (wide)
                            SizedBox(
                              width: 110,
                              child: Slider(
                                value: volume,
                                max: 100,
                                onChanged: (v) => ref.read(playerProvider.notifier).setVolume(v),
                              ),
                            ),
                          IconButton(
                            tooltip: 'Now playing',
                            onPressed: track == null ? null : () => openNowPlaying(context),
                            icon: Icon(Icons.open_in_full_rounded, color: gx.muted, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
