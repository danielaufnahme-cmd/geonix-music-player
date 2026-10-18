import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playlist.dart';
import '../state/actions.dart';
import '../state/player_controller.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/skeleton.dart';
import '../widgets/track_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller = TextEditingController(text: ref.read(searchQueryProvider));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(searchFocusProvider).requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final query = ref.watch(searchQueryProvider).trim();
    final isPlaylist = looksLikePlaylistUrl(query);

    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
        sliver: SliverToBoxAdapter(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Search', style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1)),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              focusNode: ref.watch(searchFocusProvider),
              style: text.titleMedium,
              onChanged: (v) => ref.read(searchQueryProvider.notifier).set(v),
              decoration: InputDecoration(
                hintText: 'Songs, artists, albums — or paste a YouTube Music playlist link',
                prefixIcon: Icon(Icons.search_rounded, color: gx.muted),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _controller.clear();
                          ref.read(searchQueryProvider.notifier).set('');
                          ref.read(searchFocusProvider).requestFocus();
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 20),
              ),
            ),
          ]),
        ),
      ),
      if (query.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.travel_explore_rounded,
            title: 'Find your next favourite song',
            message: 'Search YouTube Music for songs. Click a song to preview it, '
                'or hit the download button to add it to your library.\n\n'
                'Tip: paste a playlist link to download the whole playlist.',
          ),
        )
      else if (isPlaylist)
        _PlaylistImport(url: query)
      else
        const _SearchResults(),
    ]);
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(searchResultsProvider);
    return results.when(
      loading: () => const SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverToBoxAdapter(child: SkeletonTrackList()),
      ),
      error: (e, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'Search failed',
          message: e.toString(),
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(searchResultsProvider),
        ),
      ),
      data: (tracks) => tracks.isEmpty
          ? const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(icon: Icons.search_off_rounded, title: 'No songs found', message: 'Try different words.'),
            )
          : SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, kContentBottomPadding),
              sliver: SliverList.builder(
                itemCount: tracks.length,
                itemBuilder: (context, i) => ConnectedTrackTile(track: tracks[i], queue: tracks, index: i),
              ),
            ),
    );
  }
}

class _PlaylistImport extends ConsumerWidget {
  const _PlaylistImport({required this.url});
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(playlistPreviewProvider(url));
    return preview.when(
      loading: () => const SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverToBoxAdapter(child: SkeletonTrackList(count: 6)),
      ),
      error: (e, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.link_off_rounded,
          title: 'Couldn\'t open that playlist',
          message: e.toString(),
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(playlistPreviewProvider(url)),
        ),
      ),
      data: (p) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, kContentBottomPadding),
        sliver: SliverList.list(children: [
          _ImportHeader(preview: p, url: url),
          const SizedBox(height: 12),
          for (var i = 0; i < p.tracks.length; i++) ConnectedTrackTile(track: p.tracks[i], queue: p.tracks, index: i),
        ]),
      ),
    );
  }
}

class _ImportHeader extends ConsumerStatefulWidget {
  const _ImportHeader({required this.preview, required this.url});
  final PlaylistPreview preview;
  final String url;

  @override
  ConsumerState<_ImportHeader> createState() => _ImportHeaderState();
}

class _ImportHeaderState extends ConsumerState<_ImportHeader> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final p = widget.preview;
    final missing = p.tracks.where((t) => !t.downloaded).length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(colors: [gx.accent.withValues(alpha: 0.22), gx.surface]),
        border: Border.all(color: gx.outline),
      ),
      child: Row(children: [
        PlaylistCover(trackIds: [for (final t in p.tracks.take(4)) t.videoId], size: 132),
        const SizedBox(width: 24),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('YOUTUBE PLAYLIST',
                style: text.labelSmall?.copyWith(color: gx.accent, fontWeight: FontWeight.w800, letterSpacing: 1.3)),
            const SizedBox(height: 6),
            Text(p.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6)),
            const SizedBox(height: 6),
            Text('${p.tracks.length} songs · $missing to download', style: text.bodyMedium?.copyWith(color: gx.muted)),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        final id = await LibraryActions(ref).importPlaylist(widget.url);
                        if (!mounted) return;
                        setState(() => _busy = false);
                        if (id != null) ref.read(navProvider.notifier).go(PlaylistRoute(id));
                      },
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_rounded),
                label: const Text('Download all'),
              ),
              OutlinedButton.icon(
                onPressed: p.tracks.isEmpty ? null : () => ref.read(playerProvider.notifier).playList(p.tracks),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Preview'),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
