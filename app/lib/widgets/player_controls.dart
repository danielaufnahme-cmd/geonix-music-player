import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/player_controller.dart';
import '../theme.dart';

/// Shuffle · previous · play/pause · next · repeat.
class PlayerControls extends ConsumerWidget {
  const PlayerControls({super.key, this.large = false});
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final s = ref.watch(playerProvider);
    final c = ref.read(playerProvider.notifier);
    final enabled = s.current != null;
    final small = large ? 28.0 : 20.0;

    Color toggleColor(bool on) => on ? gx.accent : gx.muted;

    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: s.shuffle ? 'Shuffle on' : 'Shuffle off',
        onPressed: enabled ? c.toggleShuffle : null,
        icon: Icon(Icons.shuffle_rounded, size: small, color: toggleColor(s.shuffle)),
      ),
      SizedBox(width: large ? 12 : 4),
      IconButton(
        tooltip: 'Previous (Ctrl+←)',
        onPressed: enabled ? c.previous : null,
        icon: Icon(Icons.skip_previous_rounded, size: large ? 40 : 28),
      ),
      SizedBox(width: large ? 16 : 6),
      PlayPauseButton(size: large ? 76 : 44),
      SizedBox(width: large ? 16 : 6),
      IconButton(
        tooltip: 'Next (Ctrl+→)',
        onPressed: enabled && s.hasNext ? c.next : null,
        icon: Icon(Icons.skip_next_rounded, size: large ? 40 : 28),
      ),
      SizedBox(width: large ? 12 : 4),
      IconButton(
        tooltip: switch (s.repeat) {
          LoopMode.off => 'Repeat off',
          LoopMode.all => 'Repeat all',
          LoopMode.one => 'Repeat one',
        },
        onPressed: enabled ? c.cycleRepeat : null,
        icon: Icon(s.repeat == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
            size: small, color: toggleColor(s.repeat != LoopMode.off)),
      ),
    ]);
  }
}

/// Circular accent button whose icon morphs between play and pause.
class PlayPauseButton extends ConsumerStatefulWidget {
  const PlayPauseButton({super.key, this.size = 44});
  final double size;

  @override
  ConsumerState<PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends ConsumerState<PlayPauseButton> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  bool _hover = false;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final playing = ref.watch(playerProvider.select((s) => s.playing));
    final enabled = ref.watch(currentTrackProvider) != null;
    final buffering = ref.watch(bufferingProvider).asData?.value ?? false;
    playing ? _anim.forward() : _anim.reverse();

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover && enabled ? 1.07 : 1,
        duration: const Duration(milliseconds: 160),
        child: Tooltip(
          message: playing ? 'Pause (Space)' : 'Play (Space)',
          child: Material(
            color: enabled ? gx.accent : gx.surfaceHigh,
            shape: const CircleBorder(),
            elevation: enabled ? 6 : 0,
            shadowColor: gx.accent.withValues(alpha: 0.6),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? () => ref.read(playerProvider.notifier).playPause() : null,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Stack(alignment: Alignment.center, children: [
                  AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress: _anim,
                    size: widget.size * 0.52,
                    color: enabled ? gx.onAccent : gx.muted,
                  ),
                  if (buffering && enabled)
                    SizedBox(
                      width: widget.size - 4,
                      height: widget.size - 4,
                      child: CircularProgressIndicator(strokeWidth: 2, color: gx.onAccent.withValues(alpha: 0.7)),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
