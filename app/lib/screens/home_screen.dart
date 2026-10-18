import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../state/actions.dart';
import '../state/player_controller.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/waves.dart';
import '../util/format.dart';
import '../widgets/cover_card.dart';
import '../widgets/cover_image.dart';
import '../widgets/empty_state.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/section_row.dart';
import '../widgets/skeleton.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final library = ref.watch(libraryTracksProvider);
    final recent = ref.watch(recentlyPlayedProvider);
    final top = ref.watch(topTracksProvider);
    final recs = ref.watch(recommendationsProvider);
    final playlists = ref.watch(playlistsProvider);
    final player = ref.read(playerProvider.notifier);
    final actions = LibraryActions(ref);

    final libraryEmpty = library.asData?.value.isEmpty ?? false;
    final hasError = library.hasError;

    Widget trackRow(
      String title,
      AsyncValue<List<Track>> value, {
      String? subtitle,
      bool downloadable = false,
      Widget? action,
    }) {
      return value.when(
        loading: () => Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              const SkeletonCardRow(),
            ],
          ),
        ),
        error: (e, _) => const SizedBox.shrink(),
        data: (tracks) => tracks.isEmpty
            ? const SizedBox.shrink()
            : SectionRow(
                title: title,
                subtitle: subtitle,
                action: action,
                itemCount: tracks.length,
                itemBuilder: (context, i) => CoverCard(
                  image: CoverImage(videoId: tracks[i].videoId, radius: 16),
                  title: tracks[i].title,
                  subtitle: tracks[i].artist,
                  onPlay: () => player.playList(tracks, start: i),
                  onDownload: downloadable && !tracks[i].downloaded ? () => actions.download(tracks[i]) : null,
                ),
              ),
      );
    }

    // "Because you listened to <Artist>": the biggest group of recommendations.
    final recList = recs.asData?.value ?? const <Track>[];
    final groups = <String, List<Track>>{};
    for (final t in recList) {
      if (t.becauseArtist != null && t.becauseArtist!.isNotEmpty) {
        groups.putIfAbsent(t.becauseArtist!, () => []).add(t);
      }
    }
    final becauseGroups = groups.entries.where((e) => e.value.length >= 3).toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: WaveHeaderBackground(
            color: gx.accent.withValues(alpha: 0.24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting(),
                          style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2),
                        ),
                        const SizedBox(height: 4),
                        Text('Your music, your way.', style: text.titleMedium?.copyWith(color: gx.muted)),
                      ],
                    ),
                  ),
                  if (!libraryEmpty)
                    FilledButton.tonalIcon(
                      onPressed: recs.isLoading ? null : () => ref.read(recommendationsProvider.notifier).refresh(),
                      icon: recs.isLoading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome_rounded),
                      label: const Text('Refresh For You'),
                    ),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, kContentBottomPadding),
          sliver: SliverList.list(
            children: [
              if (hasError)
                EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Can\'t reach the Geonix backend',
                  message: library.error.toString(),
                  actionLabel: 'Try again',
                  onAction: () => refreshLibrary(ref.invalidate),
                )
              else if (libraryEmpty)
                EmptyState(
                  icon: Icons.library_music_rounded,
                  title: 'Your library is empty',
                  message: 'Search for a song to get started — or paste a YouTube Music playlist link to import it.',
                  actionLabel: 'Search music',
                  onAction: () => ref.read(navProvider.notifier).go(const SearchRoute()),
                )
              else ...[
                trackRow('Recently played', recent, subtitle: 'Jump back in'),
                trackRow('Your top songs', top, subtitle: 'On repeat'),
                trackRow('Recommended for you', recs, subtitle: 'Made for you', downloadable: true),
                for (final g in becauseGroups.take(2))
                  trackRow(
                    'Because you listened to ${g.key}',
                    AsyncData(g.value),
                    subtitle: 'More like this',
                    downloadable: true,
                  ),
                playlists.maybeWhen(
                  data: (list) => list.isEmpty
                      ? const SizedBox.shrink()
                      : SectionRow(
                          title: 'Your playlists',
                          itemCount: list.length,
                          itemBuilder: (context, i) => CoverCard(
                            image: PlaylistCover(trackIds: list[i].coverTrackIds, discover: list[i].isDiscover),
                            title: list[i].name,
                            subtitle: list[i].isDiscover ? 'Made for you' : '${list[i].trackCount} songs',
                            onTap: () => ref.read(navProvider.notifier).push(PlaylistRoute(list[i].id)),
                            onPlay: () async {
                              final full = await ref.read(playlistProvider(list[i].id).future);
                              await player.playList(full.tracks);
                            },
                          ),
                        ),
                  orElse: () => const SizedBox.shrink(),
                ),
                trackRow(
                  'Recently added',
                  library.whenData((t) => t.take(16).toList()),
                  subtitle: 'Fresh in your library',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
