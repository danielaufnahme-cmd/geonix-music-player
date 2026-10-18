import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/player_controller.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../util/perf.dart';
import '../widgets/player_bar.dart';
import '../widgets/queue_panel.dart';
import '../widgets/sidebar.dart';
import '../widgets/waves.dart';
import 'downloads_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'now_playing_screen.dart';
import 'playlist_screen.dart';
import 'search_screen.dart';
import 'track_list_screen.dart';

/// Main layout: sidebar · page · optional queue, with the glass player bar
/// floating over the bottom. Also owns the global keyboard shortcuts.
class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    // Start listening for download progress right away.
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(downloadsProvider));
    if (kPerf && kPerfAutoSeconds > 0) WidgetsBinding.instance.addPostFrameCallback((_) => _perfScript());
  }

  /// GEONIX_PERF measurement run: play (muted) on the song list, open Now
  /// Playing, stay [kPerfAutoSeconds], close it, then quit. Each step is a
  /// separate phase in the frame-timing log.
  Future<void> _perfScript() async {
    Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
    ref.read(navProvider.notifier).go(const LibraryRoute(0));
    await wait(3000);
    final tracks = await ref.read(libraryTracksProvider.future);
    final player = ref.read(playerProvider.notifier);
    player.setVolume(0);
    if (tracks.isNotEmpty) await player.playList(tracks);
    await wait(1500);
    Perf.phase('shell, playing');
    await wait(4000);
    if (!mounted) return;
    Perf.phase('open Now Playing (transition)');
    openNowPlaying(context);
    await wait(700);
    Perf.phase('Now Playing, steady');
    await wait(kPerfAutoSeconds * 1000);
    if (!mounted) return;
    Perf.phase('close Now Playing (transition)');
    Navigator.of(context).maybePop();
    await wait(700);
    Perf.phase('shell, playing again');
    await wait(3000);
    await Perf.finishAndExit();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// True while the user is typing in a text field.
  bool _editingText() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final key = event.logicalKey;

    if (ctrl && key == LogicalKeyboardKey.keyF) {
      ref.read(navProvider.notifier).go(const SearchRoute());
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(searchFocusProvider).requestFocus());
      return true;
    }
    // Leave Space and Ctrl+arrows to text fields while typing.
    if (_editingText()) return false;
    final player = ref.read(playerProvider.notifier);
    if (key == LogicalKeyboardKey.space && !ctrl) {
      player.playPause();
      return true;
    }
    if (ctrl && key == LogicalKeyboardKey.arrowRight) {
      player.next();
      return true;
    }
    if (ctrl && key == LogicalKeyboardKey.arrowLeft) {
      player.previous();
      return true;
    }
    return false;
  }

  Widget _page(AppRoute route) => switch (route) {
    HomeRoute() => const HomeScreen(),
    SearchRoute() => const SearchScreen(),
    LibraryRoute(:final tab) => LibraryScreen(initialTab: tab),
    DownloadsRoute() => const DownloadsScreen(),
    PlaylistRoute(:final id) => PlaylistScreen(id: id),
    ArtistRoute(:final name) => TrackListScreen.artist(name: name),
    AlbumRoute(:final name, :final artist) => TrackListScreen.album(name: name, artist: artist),
  };

  String _key(AppRoute r) => switch (r) {
    HomeRoute() => 'home',
    SearchRoute() => 'search',
    LibraryRoute(:final tab) => 'library-$tab',
    DownloadsRoute() => 'downloads',
    PlaylistRoute(:final id) => 'playlist-$id',
    ArtistRoute(:final name) => 'artist-$name',
    AlbumRoute(:final name, :final artist) => 'album-$artist-$name',
  };

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final stack = ref.watch(navProvider);
    final route = stack.last;
    final width = MediaQuery.sizeOf(context).width;
    final queueOpen = ref.watch(queueOpenProvider) && width > 1150;
    final collapsed = width < 1120 || (queueOpen && width < 1400);

    final palette = ref.watch(currentPaletteProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: gx.background,
      body: Stack(
        children: [
          // Calm shared wave/aurora backdrop behind sidebar and pages.
          Positioned.fill(
            child: WaveBackground(
              accent: gx.accent,
              deep: palette.deep,
              intensity: dark ? 0.38 : 0.55,
              heightFactor: 0.42,
              layers: 3,
              reducedRate: true,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Sidebar(collapsed: collapsed),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                    // Translucent so the wave backdrop glows through, dense enough
                    // that lists stay easy to read.
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.alphaBlend(
                          gx.accent.withValues(alpha: 0.08),
                          gx.surface,
                        ).withValues(alpha: dark ? 0.62 : 0.70),
                        gx.background.withValues(alpha: dark ? 0.70 : 0.74),
                      ],
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0.015, 0), end: Offset.zero).animate(a),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(key: ValueKey(_key(route)), child: _page(route)),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: queueOpen ? const QueuePanel() : const SizedBox(width: 0),
              ),
            ],
          ),
          Positioned(left: collapsed ? 108 : 280, right: queueOpen ? 354 : 24, bottom: 16, child: const PlayerBar()),
        ],
      ),
    );
  }
}
