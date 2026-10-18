import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../state/actions.dart';
import '../state/player_controller.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/cover_card.dart';
import '../widgets/cover_image.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_header.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/skeleton.dart';
import '../widgets/track_tile.dart';

const _sorts = {
  'added': 'Date added',
  'title': 'Title',
  'artist': 'Artist',
  'album': 'Album',
  'plays': 'Most played',
  'recent': 'Recently played',
};

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  late int _tab = widget.initialTab;
  late final _filter = TextEditingController(text: ref.read(libraryFilterProvider));

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final tracks = ref.watch(filteredLibraryProvider);
    final count = ref.watch(libraryTracksProvider).asData?.value.length;

    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
        sliver: SliverToBoxAdapter(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PageHeader(
              title: 'Library',
              subtitle: count == null ? null : plural(count, 'song'),
              actions: [
                if (_tab == 0 && (tracks.asData?.value.isNotEmpty ?? false)) ...[
                  OutlinedButton.icon(
                    onPressed: () => ref.read(playerProvider.notifier).playList(tracks.asData!.value, shuffle: true),
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text('Shuffle'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => ref.read(playerProvider.notifier).playList(tracks.asData!.value, shuffle: false),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play all'),
                  ),
                ],
              ],
            ),
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _Tabs(
                labels: const ['Songs', 'Artists', 'Albums', 'Playlists'],
                selected: _tab,
                onSelect: (i) => setState(() => _tab = i),
              ),
              if (_tab == 0) ...[
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _filter,
                    onChanged: (v) => ref.read(libraryFilterProvider.notifier).set(v),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Filter songs',
                      prefixIcon: Icon(Icons.filter_list_rounded, color: gx.muted, size: 20),
                    ),
                  ),
                ),
                _SortMenu(),
              ],
            ]),
            const SizedBox(height: 16),
          ]),
        ),
      ),
      switch (_tab) {
        0 => _SongsTab(tracks: tracks),
        1 => const _ArtistsTab(),
        2 => const _AlbumsTab(),
        _ => const _PlaylistsTab(),
      },
    ]);
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.labels, required this.selected, required this.onSelect});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: gx.surfaceHigh, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < labels.length; i++)
          GestureDetector(
            onTap: () => onSelect(i),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: i == selected ? gx.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(labels[i],
                    style: text.labelLarge?.copyWith(
                        color: i == selected ? gx.onAccent : gx.muted, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _SortMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(librarySortProvider);
    return PopupMenuButton<String>(
      tooltip: 'Sort',
      initialValue: sort,
      onSelected: (v) => ref.read(librarySortProvider.notifier).set(v),
      itemBuilder: (_) => [for (final e in _sorts.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: context.gx.surfaceHigh, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.sort_rounded, size: 18, color: context.gx.muted),
          const SizedBox(width: 8),
          Text(_sorts[sort] ?? 'Sort'),
          const Icon(Icons.arrow_drop_down_rounded),
        ]),
      ),
    );
  }
}

class _SongsTab extends ConsumerWidget {
  const _SongsTab({required this.tracks});
  final AsyncValue<List<Track>> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return tracks.when(
      loading: () => const SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverToBoxAdapter(child: SkeletonTrackList()),
      ),
      error: (e, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Couldn\'t load your library',
          message: e.toString(),
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(libraryTracksProvider),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          final filtering = ref.read(libraryFilterProvider).isNotEmpty;
          return SliverFillRemaining(
            hasScrollBody: false,
            child: filtering
                ? const EmptyState(icon: Icons.search_off_rounded, title: 'No matching songs')
                : EmptyState(
                    icon: Icons.library_music_rounded,
                    title: 'Your library is empty',
                    message: 'Search for a song to get started.',
                    actionLabel: 'Search music',
                    onAction: () => ref.read(navProvider.notifier).go(const SearchRoute()),
                  ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, kContentBottomPadding),
          sliver: SliverList.builder(
            itemCount: list.length,
            itemBuilder: (context, i) => ConnectedTrackTile(track: list[i], queue: list, index: i),
          ),
        );
      },
    );
  }
}

SliverGridDelegate _gridDelegate() =>
    const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisExtent: 268, crossAxisSpacing: 8);

class _ArtistsTab extends ConsumerWidget {
  const _ArtistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);
    return artists.when(
      loading: () => const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.symmetric(horizontal: 28), child: SkeletonCardRow())),
      error: (e, _) => SliverToBoxAdapter(child: EmptyState(icon: Icons.error_outline, title: e.toString())),
      data: (list) => list.isEmpty
          ? const SliverFillRemaining(
              hasScrollBody: false, child: EmptyState(icon: Icons.person_rounded, title: 'No artists yet'))
          : SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, kContentBottomPadding),
              sliver: SliverGrid.builder(
                gridDelegate: _gridDelegate(),
                itemCount: list.length,
                itemBuilder: (context, i) => CoverCard(
                  circle: true,
                  width: 170,
                  image: CoverImage(videoId: list[i].coverTrackId, circle: true),
                  title: list[i].name.isEmpty ? 'Unknown artist' : list[i].name,
                  subtitle: plural(list[i].trackCount, 'song'),
                  onTap: () => ref.read(navProvider.notifier).push(ArtistRoute(list[i].name)),
                ),
              ),
            ),
    );
  }
}

class _AlbumsTab extends ConsumerWidget {
  const _AlbumsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    return albums.when(
      loading: () => const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.symmetric(horizontal: 28), child: SkeletonCardRow())),
      error: (e, _) => SliverToBoxAdapter(child: EmptyState(icon: Icons.error_outline, title: e.toString())),
      data: (list) => list.isEmpty
          ? const SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Icons.album_rounded, title: 'No albums yet'))
          : SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, kContentBottomPadding),
              sliver: SliverGrid.builder(
                gridDelegate: _gridDelegate(),
                itemCount: list.length,
                itemBuilder: (context, i) => CoverCard(
                  width: 170,
                  image: CoverImage(videoId: list[i].coverTrackId, radius: 16),
                  title: list[i].name,
                  subtitle: list[i].artist,
                  onTap: () => ref.read(navProvider.notifier).push(AlbumRoute(list[i].name, list[i].artist)),
                ),
              ),
            ),
    );
  }
}

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final gx = context.gx;
    return playlists.when(
      loading: () => const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.symmetric(horizontal: 28), child: SkeletonCardRow())),
      error: (e, _) => SliverToBoxAdapter(child: EmptyState(icon: Icons.error_outline, title: e.toString())),
      data: (list) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, kContentBottomPadding),
        sliver: SliverGrid.builder(
          gridDelegate: _gridDelegate(),
          itemCount: list.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return CoverCard(
                width: 170,
                image: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: gx.outline, width: 2),
                    color: gx.surfaceHigh,
                  ),
                  child: Icon(Icons.add_rounded, size: 56, color: gx.accent),
                ),
                title: 'New playlist',
                subtitle: 'Empty or from YouTube Music',
                onTap: () async {
                  final p = await LibraryActions(ref).createPlaylist(context);
                  if (p != null) ref.read(navProvider.notifier).push(PlaylistRoute(p.id));
                },
              );
            }
            final p = list[i - 1];
            return CoverCard(
              width: 170,
              image: PlaylistCover(trackIds: p.coverTrackIds, size: 170, discover: p.isDiscover),
              title: p.name,
              subtitle: p.isDiscover ? 'Made for you' : plural(p.trackCount, 'song'),
              onTap: () => ref.read(navProvider.notifier).push(PlaylistRoute(p.id)),
            );
          },
        ),
      ),
    );
  }
}
