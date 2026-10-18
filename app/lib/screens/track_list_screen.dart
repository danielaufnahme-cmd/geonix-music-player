import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/player_controller.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/cover_image.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_header.dart';
import '../widgets/skeleton.dart';
import '../widgets/track_tile.dart';

/// Songs of one artist or one album from the library.
class TrackListScreen extends ConsumerWidget {
  const TrackListScreen.artist({super.key, required String name})
      : title = name,
        artist = name,
        album = null;

  const TrackListScreen.album({super.key, required String name, required String this.artist})
      : title = name,
        album = name;

  final String title;
  final String? artist;
  final String? album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final all = ref.watch(libraryTracksProvider);
    final isArtist = album == null;

    return all.when(
      loading: () => const Padding(padding: EdgeInsets.all(28), child: SkeletonTrackList()),
      error: (e, _) => EmptyState(icon: Icons.error_outline, title: e.toString()),
      data: (tracks) {
        final list = tracks
            .where((t) => isArtist
                ? t.artist.toLowerCase() == artist!.toLowerCase()
                : t.album.toLowerCase() == album!.toLowerCase() && t.artist.toLowerCase() == artist!.toLowerCase())
            .toList();
        final total = list.fold<int>(0, (s, t) => s + t.durationSec);
        return CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (ref.watch(navProvider).length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: BackButtonCircle(onTap: () => ref.read(navProvider.notifier).pop()),
                  ),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: isArtist ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: isArtist ? null : BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 30, offset: Offset(0, 14))],
                    ),
                    child: CoverImage(
                      videoId: list.isEmpty ? '' : list.first.videoId,
                      size: 190,
                      radius: 20,
                      circle: isArtist,
                    ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(isArtist ? 'ARTIST' : 'ALBUM · ${artist!}',
                          style: text.labelMedium?.copyWith(color: gx.accent, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                      const SizedBox(height: 8),
                      Text(title.isEmpty ? 'Unknown' : title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.displayMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1.5)),
                      const SizedBox(height: 10),
                      Text('${plural(list.length, 'song')} · ${formatTotal(total)}',
                          style: text.bodyLarge?.copyWith(color: gx.muted)),
                      const SizedBox(height: 18),
                      Wrap(spacing: 12, children: [
                        FilledButton.icon(
                          onPressed: list.isEmpty ? null : () => ref.read(playerProvider.notifier).playList(list, shuffle: false),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Play'),
                        ),
                        OutlinedButton.icon(
                          onPressed: list.isEmpty ? null : () => ref.read(playerProvider.notifier).playList(list, shuffle: true),
                          icon: const Icon(Icons.shuffle_rounded),
                          label: const Text('Shuffle'),
                        ),
                      ]),
                    ]),
                  ),
                ]),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, kContentBottomPadding),
            sliver: SliverList.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => ConnectedTrackTile(track: list[i], queue: list, index: i, showAlbum: isArtist),
            ),
          ),
        ]);
      },
    );
  }
}
