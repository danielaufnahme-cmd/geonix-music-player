import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../state/actions.dart';
import '../state/player_controller.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_header.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/skeleton.dart';
import '../widgets/track_tile.dart';
import '../widgets/waves.dart';

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistProvider(id));
    return playlist.when(
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(28, 40, 28, 0),
        child: Column(
          children: [
            Shimmer(
              child: Row(
                children: [
                  SkeletonBox(width: 200, height: 200, radius: 20),
                  SizedBox(width: 28),
                  Expanded(child: SkeletonBox(height: 40)),
                ],
              ),
            ),
            SizedBox(height: 28),
            SkeletonTrackList(),
          ],
        ),
      ),
      error: (e, _) => EmptyState(
        icon: Icons.playlist_remove_rounded,
        title: 'Playlist not available',
        message: e.toString(),
        actionLabel: 'Back to library',
        onAction: () => ref.read(navProvider.notifier).go(const LibraryRoute(3)),
      ),
      data: (p) => _PlaylistBody(key: ValueKey(p.id), playlist: p),
    );
  }
}

class _PlaylistBody extends ConsumerStatefulWidget {
  const _PlaylistBody({super.key, required this.playlist});
  final Playlist playlist;

  @override
  ConsumerState<_PlaylistBody> createState() => _PlaylistBodyState();
}

class _PlaylistBodyState extends ConsumerState<_PlaylistBody> {
  /// Local order for instant drag-and-drop feedback.
  late List<Track> _tracks = widget.playlist.tracks;

  @override
  void didUpdateWidget(covariant _PlaylistBody old) {
    super.didUpdateWidget(old);
    _tracks = widget.playlist.tracks;
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final before = _tracks;
    final next = List<Track>.of(_tracks);
    next.insert(newIndex, next.removeAt(oldIndex));
    setState(() => _tracks = next);
    try {
      await ref.read(apiProvider).reorderPlaylist(widget.playlist.id, [for (final t in next) t.videoId]);
      ref.invalidate(playlistsProvider);
      ref.invalidate(playlistProvider(widget.playlist.id));
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _tracks = before);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not reorder: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final p = widget.playlist;
    final actions = LibraryActions(ref);
    final player = ref.read(playerProvider.notifier);
    final recsLoading = ref.watch(recommendationsProvider).isLoading;
    final notDownloaded = _tracks.where((t) => !t.downloaded).length;
    final canReorder = !p.isDiscover && _tracks.length > 1;
    final label = switch (p.kind) {
      'discover' => 'DISCOVER MIX · MADE FOR YOU',
      'imported' => 'IMPORTED PLAYLIST',
      _ => 'PLAYLIST',
    };

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: WaveHeaderBackground(
            color: gx.accent.withValues(alpha: 0.30),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ref.watch(navProvider).length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: BackButtonCircle(onTap: () => ref.read(navProvider.notifier).pop()),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 36, offset: Offset(0, 18))],
                        ),
                        child: PlaylistCover(trackIds: p.coverTrackIds, size: 210, radius: 20, discover: p.isDiscover),
                      ),
                      const SizedBox(width: 28),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: text.labelMedium?.copyWith(
                                color: gx.accent,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              p.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.displayMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1.5),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              [
                                plural(p.trackCount, 'song'),
                                if (p.durationSec > 0) formatTotal(p.durationSec),
                              ].join(' · '),
                              style: text.bodyLarge?.copyWith(color: gx.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _tracks.isEmpty ? null : () => player.playList(_tracks, shuffle: false),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 26),
                        label: const Text('Play'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _tracks.isEmpty ? null : () => player.playList(_tracks, shuffle: true),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                        ),
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('Shuffle'),
                      ),
                      if (notDownloaded > 0)
                        OutlinedButton.icon(
                          onPressed: () => actions.downloadAll(_tracks),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                          ),
                          icon: const Icon(Icons.download_rounded),
                          label: Text('Download all ($notDownloaded)'),
                        ),
                      if (p.isDiscover)
                        OutlinedButton.icon(
                          onPressed: recsLoading ? null : () => ref.read(recommendationsProvider.notifier).refresh(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                          ),
                          icon: recsLoading
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.auto_awesome_rounded),
                          label: const Text('New mix'),
                        )
                      else
                        PopupMenuButton<String>(
                          tooltip: 'More',
                          icon: const Icon(Icons.more_horiz_rounded),
                          onSelected: (v) async {
                            if (v == 'import') {
                              await actions.importIntoPlaylist(context, p);
                            } else if (v == 'rename') {
                              await actions.renamePlaylist(context, p);
                            } else if (v == 'delete') {
                              if (await actions.deletePlaylist(context, p)) {
                                ref.read(navProvider.notifier).go(const LibraryRoute(3));
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'import',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.playlist_add_rounded),
                                title: Text('Import from YouTube Music'),
                              ),
                            ),
                            PopupMenuDivider(),
                            PopupMenuItem(value: 'rename', child: Text('Rename')),
                            PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_tracks.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: p.isDiscover ? Icons.auto_awesome_rounded : Icons.queue_music_rounded,
              title: p.isDiscover ? 'Your mix is being prepared' : 'This playlist is empty',
              message: p.isDiscover
                  ? 'Press “New mix” to build it from your listening.'
                  : 'Add songs with the ⋯ menu on any song, or import a whole YouTube Music playlist.',
              actionLabel: p.isDiscover ? null : 'Import from YouTube Music',
              actionIcon: Icons.playlist_add_rounded,
              onAction: p.isDiscover ? null : () => actions.importIntoPlaylist(context, p),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, kContentBottomPadding),
            sliver: SliverReorderableList(
              itemCount: _tracks.length,
              onReorderItem: _reorder,
              proxyDecorator: (child, _, _) => Material(
                color: gx.surfaceHigh,
                elevation: 10,
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(12),
                child: child,
              ),
              itemBuilder: (context, i) => ConnectedTrackTile(
                key: ValueKey(_tracks[i].videoId),
                track: _tracks[i],
                queue: _tracks,
                index: i,
                playlist: p,
                dragHandle: canReorder
                    ? ReorderableDragStartListener(
                        index: i,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.drag_indicator_rounded, color: gx.muted, size: 20),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
