import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/actions.dart';
import '../state/player_controller.dart';
import '../theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_panel.dart';
import '../widgets/player_controls.dart';
import '../widgets/seek_bar.dart';
import '../widgets/waves.dart';

void openNowPlaying(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      // Opaque: once the slide finishes the shell (and its waves) below stops
      // being painted at all.
      opaque: true,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => const RepaintBoundary(child: NowPlayingScreen()),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    ),
  );
}

/// Whether the full-screen side panel (Up next / Lyrics) is shown. Null
/// means "automatic": shown on wide windows, hidden on narrow ones.
class NowPlayingPanelOpen extends Notifier<bool?> {
  @override
  bool? build() => null;
  void toggle({required bool wide}) => state = !(state ?? wide);
  void open() => state = true;
}

final nowPlayingPanelOpenProvider = NotifierProvider<NowPlayingPanelOpen, bool?>(NowPlayingPanelOpen.new);

/// Windows narrower than this show the side panel over the player instead of beside it.
const double kSidePanelMinWidth = 1100;

/// Full-screen player: big cover with a breathing glow over a moving aurora
/// and layered waves, all colored from the cover. Lyrics run under the
/// controls; the side panel holds the queue and the full lyrics.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final track = ref.watch(currentTrackProvider);
    final palette = ref.watch(currentPaletteProvider);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= kSidePanelMinWidth;
    final panelOpen = ref.watch(nowPlayingPanelOpenProvider) ?? wide;
    final coverSize = (size.height * 0.40).clamp(200.0, 500.0).toDouble();
    void openLyrics() {
      ref.read(nowPlayingTabProvider.notifier).show(NowPlayingTab.lyrics);
      ref.read(nowPlayingPanelOpenProvider.notifier).open();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Keeps text crisp where it sits over the waves.
    final textShadow = [Shadow(color: (dark ? Colors.black : Colors.white).withValues(alpha: 0.45), blurRadius: 12)];

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: gx.background,
          body: Stack(
            children: [
              Positioned.fill(
                child: WaveBackground(
                  accent: gx.accent,
                  deep: palette.deep,
                  heightFactor: 0.42,
                  glow: dark,
                  vignette: dark ? 0.5 : 0.12,
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Close (Esc)',
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                          ),
                          Expanded(
                            child: Text(
                              'NOW PLAYING',
                              textAlign: TextAlign.center,
                              style: text.labelMedium?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            tooltip: panelOpen ? 'Hide up next & lyrics' : 'Show up next & lyrics',
                            onPressed: () => ref.read(nowPlayingPanelOpenProvider.notifier).toggle(wide: wide),
                            isSelected: panelOpen,
                            icon: const Icon(Icons.view_sidebar_outlined),
                            selectedIcon: Icon(Icons.view_sidebar_rounded, color: gx.accent),
                          ),
                          if (track != null)
                            IconButton(
                              tooltip: 'Add to playlist',
                              onPressed: () => LibraryActions(ref).addToPlaylist(context, track),
                              icon: const Icon(Icons.playlist_add_rounded),
                            )
                          else
                            const SizedBox(width: 48),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Stack(children: [
                        Row(children: [
                    Expanded(
                      child: Center(
                        child: track == null
                            ? Text('Nothing is playing', style: text.titleMedium)
                            : SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 450),
                                      transitionBuilder: (child, a) => FadeTransition(
                                        opacity: a,
                                        child: ScaleTransition(
                                          scale: Tween(begin: 0.94, end: 1.0).animate(a),
                                          child: child,
                                        ),
                                      ),
                                      child: BreathingGlow(
                                        key: ValueKey(track.videoId),
                                        color: gx.accent,
                                        radius: 28,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(28),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: dark ? 0.5 : 0.18),
                                                blurRadius: 40,
                                                offset: const Offset(0, 24),
                                              ),
                                            ],
                                          ),
                                          child: Hero(
                                            tag: 'now-playing-cover',
                                            child: CoverImage(videoId: track.videoId, size: coverSize, radius: 28),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 36),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 640),
                                      child: Column(
                                        children: [
                                          Text(
                                            track.title,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: text.headlineMedium?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.6,
                                              shadows: textShadow,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            [track.artist, if (track.album.isNotEmpty) track.album].join(' · '),
                                            textAlign: TextAlign.center,
                                            style: text.titleMedium?.copyWith(
                                              color: Color.lerp(gx.muted, gx.text, 0.35),
                                              shadows: textShadow,
                                            ),
                                          ),
                                          const SizedBox(height: 22),
                                          const SeekBar(large: true),
                                          const SizedBox(height: 10),
                                          const PlayerControls(large: true),
                                          const SizedBox(height: 14),
                                          LyricsStrip(onOpen: openLyrics),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                          // Beside the player on wide windows.
                          AnimatedSize(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            child: wide && panelOpen
                                ? const Padding(
                                    padding: EdgeInsets.fromLTRB(8, 8, 20, 8),
                                    child: SizedBox(width: 380, child: NowPlayingPanel()),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ]),
                        // Over the player on narrow windows.
                        if (!wide)
                          Positioned(
                            top: 8,
                            bottom: 8,
                            right: 12,
                            width: (size.width * 0.9).clamp(0, 380).toDouble(),
                            child: IgnorePointer(
                              ignoring: !panelOpen,
                              child: AnimatedSlide(
                                offset: panelOpen ? Offset.zero : const Offset(1.08, 0),
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                child: NowPlayingPanel(
                                  onClose: () => ref.read(nowPlayingPanelOpenProvider.notifier).toggle(wide: wide),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 24),
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
