import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/player_controller.dart';
import '../theme.dart';
import '../util/format.dart';
import 'waves.dart';

/// Position bar. The played part is a travelling wave while music plays.
/// Click or drag to seek; while dragging it follows the pointer (and goes
/// flat) instead of fighting with the live playback position.
class SeekBar extends ConsumerStatefulWidget {
  const SeekBar({super.key, this.large = false});
  final bool large;

  @override
  ConsumerState<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<SeekBar> {
  double? _drag;

  double _fractionAt(double dx, double width) {
    const inset = WavySeekPainter.inset;
    if (width <= inset * 2) return 0;
    return ((dx - inset) / (width - inset * 2)).clamp(0.0, 1.0);
  }

  void _seekTo(double fraction, Duration duration) {
    ref.read(playerProvider.notifier).seek(Duration(milliseconds: (fraction * duration.inMilliseconds).round()));
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final position = ref.watch(positionProvider).asData?.value ?? Duration.zero;
    final duration = ref.watch(durationProvider).asData?.value ?? Duration.zero;
    final maxMs = duration.inMilliseconds;
    final enabled = maxMs > 0;
    final fraction = _drag ?? (enabled ? (position.inMilliseconds / maxMs).clamp(0.0, 1.0) : 0.0);
    final shownMs = (fraction * maxMs).round();
    final label = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: gx.muted,
      fontFeatures: const [FontFeature.tabularFigures()],
      fontSize: widget.large ? 13 : 11,
    );

    final bar = LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        return Semantics(
          slider: true,
          label: 'Seek',
          value: formatDuration(Duration(milliseconds: shownMs)),
          onIncrease: enabled ? () => _seekTo(((shownMs + 5000) / maxMs).clamp(0.0, 1.0), duration) : null,
          onDecrease: enabled ? () => _seekTo(((shownMs - 5000) / maxMs).clamp(0.0, 1.0), duration) : null,
          child: MouseRegion(
            cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: enabled ? (d) => _seekTo(_fractionAt(d.localPosition.dx, width), duration) : null,
              onHorizontalDragStart: enabled
                  ? (d) => setState(() => _drag = _fractionAt(d.localPosition.dx, width))
                  : null,
              onHorizontalDragUpdate: enabled
                  ? (d) => setState(() => _drag = _fractionAt(d.localPosition.dx, width))
                  : null,
              onHorizontalDragEnd: enabled
                  ? (_) {
                      if (_drag != null) _seekTo(_drag!, duration);
                      setState(() => _drag = null);
                    }
                  : null,
              onHorizontalDragCancel: () => setState(() => _drag = null),
              child: SizedBox(
                height: widget.large ? 34 : 22,
                width: double.infinity,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: WavySeekPainter(
                      clock: context.waveClock,
                      fraction: fraction,
                      active: enabled ? gx.accent : gx.muted.withValues(alpha: 0.5),
                      inactive: gx.muted.withValues(alpha: 0.28),
                      large: widget.large,
                      flat: _drag != null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    final elapsed = Text(formatDuration(Duration(milliseconds: shownMs)), style: label);
    final total = Text(formatDuration(duration), style: label);
    if (widget.large) {
      return Column(
        children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: bar),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [elapsed, total]),
          ),
        ],
      );
    }
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Align(alignment: Alignment.centerRight, child: elapsed),
        ),
        const SizedBox(width: 6),
        Expanded(child: bar),
        const SizedBox(width: 6),
        SizedBox(width: 44, child: total),
      ],
    );
  }
}
