import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lyrics.dart';
import '../state/player_controller.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'skeleton.dart';

/// Lyrics of the playing song (empty while nothing plays).
final currentLyricsProvider = Provider<AsyncValue<Lyrics>>((ref) {
  final track = ref.watch(currentTrackProvider);
  if (track == null) return const AsyncValue.data(Lyrics.none);
  return ref.watch(lyricsProvider(track.videoId));
});

/// Index of the line being sung. Rebuilds listeners only when the line changes,
/// not on every position tick.
final currentLyricLineProvider = Provider<int>((ref) {
  final lyrics = ref.watch(currentLyricsProvider).asData?.value;
  if (lyrics == null || !lyrics.synced) return -1;
  final position = ref.watch(positionProvider).asData?.value ?? Duration.zero;
  return lyrics.lineAt(position);
});

String _display(String text) => text.isEmpty ? '♪' : text;

/// Three karaoke lines under the player controls: previous, current, next.
/// Tapping it opens the full lyrics.
class LyricsStrip extends ConsumerWidget {
  const LyricsStrip({super.key, this.onOpen});
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final lyrics = ref.watch(currentLyricsProvider);
    return lyrics.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Shimmer(child: Column(children: [SkeletonBox(width: 260, height: 14), SizedBox(height: 10), SkeletonBox(width: 200, height: 12)])),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (l) {
        if (l.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('No lyrics found for this song', style: text.bodySmall?.copyWith(color: gx.muted)),
          );
        }
        if (!l.synced) {
          return TextButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.lyrics_rounded, size: 18),
            label: const Text('Show lyrics'),
          );
        }
        final i = ref.watch(currentLyricLineProvider);
        String at(int k) => k >= 0 && k < l.lines.length ? _display(l.lines[k].text) : '';
        final current = i < 0 ? '♪' : at(i);
        return MouseRegion(
          cursor: onOpen == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                    child: child,
                  ),
                ),
                child: Column(
                  key: ValueKey(i),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(i < 0 ? '' : at(i - 1),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(color: gx.muted.withValues(alpha: 0.7))),
                    const SizedBox(height: 4),
                    Text(current,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: gx.text, height: 1.25)),
                    const SizedBox(height: 4),
                    Text(at(i + 1),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(color: gx.muted.withValues(alpha: 0.7))),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// All lyrics: the current line is highlighted and kept in view; tap a line
/// to jump there. Scrolling by hand pauses the auto-scroll for a few seconds.
class LyricsPanel extends ConsumerStatefulWidget {
  const LyricsPanel({super.key});

  @override
  ConsumerState<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends ConsumerState<LyricsPanel> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _autoScrolling = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _follow(int index) {
    if (index < 0 || DateTime.now().difference(_userScrolledAt) < const Duration(seconds: 4)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = _keys[index]?.currentContext;
      if (ctx == null || !mounted) return;
      _autoScrolling = true;
      await Scrollable.ensureVisible(ctx,
          alignment: 0.35, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
      _autoScrolling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final lyrics = ref.watch(currentLyricsProvider);
    ref.listen<int>(currentLyricLineProvider, (_, next) => _follow(next));

    return lyrics.when(
      loading: () => Shimmer(child: ListView(
        padding: const EdgeInsets.all(20),
        children: [for (final w in const <double>[220, 180, 240, 160, 200, 230]) Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SkeletonBox(width: w, height: 18),
        )],
      )),
      error: (_, _) => _empty(gx, text),
      data: (l) {
        if (l.isEmpty) return _empty(gx, text);
        final current = l.synced ? ref.watch(currentLyricLineProvider) : -1;
        final player = ref.read(playerProvider.notifier);
        return NotificationListener<UserScrollNotification>(
          onNotification: (_) {
            if (!_autoScrolling) _userScrolledAt = DateTime.now();
            return false;
          },
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            itemCount: l.lines.length + 1,
            itemBuilder: (context, i) {
              if (i == l.lines.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    [if (!l.synced) 'Not synced', if (l.source != null) 'Lyrics: ${l.source}'].join(' · '),
                    style: text.labelSmall?.copyWith(color: gx.muted),
                  ),
                );
              }
              final line = l.lines[i];
              final active = i == current;
              final past = current >= 0 && i < current;
              final style = (l.synced ? text.titleLarge : text.titleMedium)?.copyWith(
                fontWeight: l.synced ? FontWeight.w800 : FontWeight.w600,
                height: 1.3,
                color: !l.synced
                    ? gx.text
                    : active
                        ? gx.text
                        : gx.text.withValues(alpha: past ? 0.38 : 0.55),
              );
              final key = _keys.putIfAbsent(i, GlobalKey.new);
              return Padding(
                key: key,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: line.timeMs == null ? null : () {
                    _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
                    player.seek(Duration(milliseconds: line.timeMs!));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: AnimatedScale(
                      scale: active ? 1.0 : 0.96,
                      alignment: Alignment.centerLeft,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        style: style ?? const TextStyle(),
                        child: Text(_display(line.text)),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _empty(GeonixPalette gx, TextTheme text) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lyrics_outlined, size: 40, color: gx.muted),
          const SizedBox(height: 10),
          Text('No lyrics found', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('We looked on YouTube Music and LRCLIB.', style: text.bodySmall?.copyWith(color: gx.muted)),
        ]),
      );
}
