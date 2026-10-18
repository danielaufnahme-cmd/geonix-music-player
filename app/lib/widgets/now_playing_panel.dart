import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download.dart';
import '../models/track.dart';
import '../state/actions.dart';
import '../state/player_controller.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'cover_image.dart';
import 'lyrics_view.dart';
import 'track_tile.dart';

enum NowPlayingTab { upNext, lyrics }

/// Which tab of the full-screen side panel is showing.
class NowPlayingTabController extends Notifier<NowPlayingTab> {
  @override
  NowPlayingTab build() => NowPlayingTab.upNext;
  void show(NowPlayingTab tab) => state = tab;
}

final nowPlayingTabProvider = NotifierProvider<NowPlayingTabController, NowPlayingTab>(NowPlayingTabController.new);

/// Songs coming up that aren't downloaded yet (and aren't downloading).
List<Track> notDownloaded(List<Track> tracks, Map<String, Download> downloads) => [
      for (final t in tracks)
        if (!t.downloaded && !(downloads[t.videoId]?.isActive ?? false) && !(downloads[t.videoId]?.isFinished ?? false)) t
    ];

/// Frosted side card on the full-screen player: the queue (with download
/// buttons for songs not in the library) and the full lyrics.
class NowPlayingPanel extends ConsumerWidget {
  const NowPlayingPanel({super.key, this.onClose});
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final tab = ref.watch(nowPlayingTabProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    Widget tabButton(NowPlayingTab t, IconData icon, String label) {
      final selected = tab == t;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => ref.read(nowPlayingTabProvider.notifier).show(t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? gx.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18, color: selected ? gx.accent : gx.muted),
              const SizedBox(width: 8),
              Text(label,
                  style: text.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700, color: selected ? gx.text : gx.muted)),
            ]),
          ),
        ),
      );
    }

    // A translucent card instead of a live blur: blurring the moving waves
    // behind it would cost a full re-blur every frame.
    return RepaintBoundary(
      child: Container(
          decoration: BoxDecoration(
            color: gx.surface.withValues(alpha: dark ? 0.72 : 0.82),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: gx.outline),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 6, 6),
              child: Row(children: [
                tabButton(NowPlayingTab.upNext, Icons.queue_music_rounded, 'Up next'),
                const SizedBox(width: 6),
                tabButton(NowPlayingTab.lyrics, Icons.lyrics_rounded, 'Lyrics'),
                if (onClose != null)
                  IconButton(tooltip: 'Hide panel', onPressed: onClose, icon: Icon(Icons.close_rounded, color: gx.muted)),
              ]),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: tab == NowPlayingTab.upNext
                    ? const _UpNextList(key: ValueKey('up-next'))
                    : const LyricsPanel(key: ValueKey('lyrics')),
              ),
            ),
          ]),
      ),
    );
  }
}

class _UpNextList extends ConsumerWidget {
  const _UpNextList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final upNext = ref.watch(playerProvider.select((s) => s.upNext));
    final player = ref.read(playerProvider.notifier);
    final downloads = ref.watch(downloadByVideoProvider);
    final actions = LibraryActions(ref);
    final missing = notDownloaded(upNext, downloads);

    if (upNext.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.queue_music_rounded, size: 40, color: gx.muted),
            const SizedBox(height: 10),
            Text('Nothing queued', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Use “Play next” or “Add to queue” on any song.',
                textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: gx.muted)),
          ]),
        ),
      );
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(children: [
          Expanded(
            child: Text('${upNext.length} song${upNext.length == 1 ? '' : 's'}',
                style: text.labelMedium?.copyWith(color: gx.muted)),
          ),
          if (missing.isNotEmpty)
            TextButton.icon(
              onPressed: () => actions.downloadAll(missing),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text('Download ${missing.length}'),
            ),
          TextButton(onPressed: player.clearUpNext, child: const Text('Clear')),
        ]),
      ),
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          buildDefaultDragHandles: false,
          itemCount: upNext.length,
          onReorderItem: player.reorderUpNext,
          proxyDecorator: (child, _, _) => Material(
            color: gx.surfaceHigh,
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: child,
          ),
          itemBuilder: (context, i) {
            final t = upNext[i];
            return Material(
              key: ValueKey('${t.videoId}-$i'),
              color: Colors.transparent,
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.only(left: 4, right: 0),
                leading: ReorderableDragStartListener(
                  index: i,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.drag_indicator_rounded, color: gx.muted, size: 18),
                    const SizedBox(width: 4),
                    CoverImage(videoId: t.videoId, size: 40, radius: 8),
                  ]),
                ),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: gx.muted)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  DownloadIndicator(
                    track: t,
                    download: downloads[t.videoId],
                    onDownload: t.downloaded ? null : () => actions.download(t),
                  ),
                  IconButton(
                    tooltip: 'Remove from queue',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, size: 18, color: gx.muted),
                    onPressed: () => player.removeFromUpNext(i),
                  ),
                ]),
                onTap: () => player.jumpTo(i),
              ),
            );
          },
        ),
      ),
    ]);
  }
}
