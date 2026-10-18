import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../state/actions.dart';
import '../state/player_controller.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../util/format.dart';
import 'cover_image.dart';

class TrackMenuItem {
  const TrackMenuItem(this.icon, this.label, this.onSelected);
  final IconData icon;
  final String label;
  final VoidCallback onSelected;
}

/// One song row. Pure widget (no providers) so it is easy to test; use
/// [ConnectedTrackTile] in screens.
class TrackTile extends StatefulWidget {
  const TrackTile({
    super.key,
    required this.track,
    this.index,
    this.isCurrent = false,
    this.isPlaying = false,
    this.download,
    this.onTap,
    this.onDownload,
    this.menu = const [],
    this.dragHandle,
    this.showAlbum = true,
    this.showCover = true,
  });

  final Track track;
  final int? index;
  final bool isCurrent;
  final bool isPlaying;
  final Download? download;
  final VoidCallback? onTap;
  final VoidCallback? onDownload;
  final List<TrackMenuItem> menu;
  final Widget? dragHandle;
  final bool showAlbum;
  final bool showCover;

  @override
  State<TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<TrackTile> {
  bool _hover = false;

  Widget _leading(GeonixPalette gx, TextTheme text) {
    if (widget.index == null) return const SizedBox.shrink();
    Widget child;
    if (widget.isCurrent && widget.isPlaying && !_hover) {
      child = Icon(Icons.graphic_eq_rounded, color: gx.accent, size: 20, key: const ValueKey('eq'));
    } else if (_hover) {
      child = Icon(Icons.play_arrow_rounded, color: gx.text, size: 22, key: const ValueKey('play'));
    } else {
      child = Text('${widget.index! + 1}',
          key: const ValueKey('n'),
          style: text.bodyMedium?.copyWith(color: widget.isCurrent ? gx.accent : gx.muted, fontFeatures: const [
            FontFeature.tabularFigures(),
          ]));
    }
    return SizedBox(
      width: 36,
      child: Center(child: AnimatedSwitcher(duration: const Duration(milliseconds: 150), child: child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final t = widget.track;
    final titleColor = widget.isCurrent ? gx.accent : gx.text;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: widget.isCurrent
                ? gx.accent.withValues(alpha: _hover ? 0.16 : 0.1)
                : (_hover ? gx.text.withValues(alpha: 0.06) : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            ?widget.dragHandle,
            _leading(gx, text),
            if (widget.showCover) ...[
              CoverImage(videoId: t.videoId, size: 46, radius: 8),
              const SizedBox(width: 14),
            ],
            Expanded(
              flex: 5,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(color: titleColor, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(t.artist,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(color: gx.muted)),
              ]),
            ),
            if (widget.showAlbum)
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(t.album,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(color: gx.muted)),
                ),
              ),
            const SizedBox(width: 8),
            DownloadIndicator(track: widget.track, download: widget.download, onDownload: widget.onDownload),
            const SizedBox(width: 12),
            SizedBox(
              width: 48,
              child: Text(
                t.durationSec > 0 ? formatDuration(t.duration) : '',
                textAlign: TextAlign.right,
                style: text.bodyMedium?.copyWith(color: gx.muted, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            SizedBox(
              width: 40,
              child: widget.menu.isEmpty
                  ? null
                  : AnimatedOpacity(
                      opacity: _hover ? 1 : 0.35,
                      duration: const Duration(milliseconds: 150),
                      child: PopupMenuButton<int>(
                        tooltip: 'More',
                        icon: Icon(Icons.more_horiz_rounded, color: gx.muted),
                        onSelected: (i) => widget.menu[i].onSelected(),
                        itemBuilder: (_) => [
                          for (var i = 0; i < widget.menu.length; i++)
                            PopupMenuItem(
                              value: i,
                              child: Row(children: [
                                Icon(widget.menu[i].icon, size: 18),
                                const SizedBox(width: 12),
                                Text(widget.menu[i].label),
                              ]),
                            ),
                        ],
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// [TrackTile] wired to the player, the download queue and library actions.
class ConnectedTrackTile extends ConsumerWidget {
  const ConnectedTrackTile({
    super.key,
    required this.track,
    required this.queue,
    required this.index,
    this.playlist,
    this.dragHandle,
    this.showAlbum = true,
    this.showIndex = true,
  });

  final Track track;

  /// The list this row belongs to; tapping plays it from [index].
  final List<Track> queue;
  final int index;

  /// Set when shown inside a playlist (enables "Remove from playlist").
  final Playlist? playlist;
  final Widget? dragHandle;
  final bool showAlbum;
  final bool showIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentTrackProvider);
    final playing = ref.watch(playerProvider.select((s) => s.playing));
    final download = ref.watch(downloadByVideoProvider.select((m) => m[track.videoId]));
    final actions = LibraryActions(ref);
    final player = ref.read(playerProvider.notifier);
    final isCurrent = current?.videoId == track.videoId;
    final width = MediaQuery.sizeOf(context).width;

    return TrackTile(
      track: track,
      index: showIndex ? index : null,
      isCurrent: isCurrent,
      isPlaying: playing,
      download: download,
      dragHandle: dragHandle,
      showAlbum: showAlbum && width > 1150,
      onTap: () => isCurrent ? player.playPause() : player.playList(queue, start: index),
      onDownload: track.downloaded ? null : () => actions.download(track),
      menu: [
        TrackMenuItem(Icons.queue_play_next_rounded, 'Play next', () => player.playNext(track)),
        TrackMenuItem(Icons.playlist_play_rounded, 'Add to queue', () => player.addToQueue(track)),
        TrackMenuItem(Icons.playlist_add_rounded, 'Add to playlist…', () => actions.addToPlaylist(context, track)),
        if (!track.downloaded) TrackMenuItem(Icons.download_rounded, 'Download', () => actions.download(track)),
        if (playlist != null && !playlist!.isDiscover)
          TrackMenuItem(Icons.remove_circle_outline_rounded, 'Remove from this playlist',
              () => actions.removeFromPlaylist(playlist!, track)),
        if (track.downloaded)
          TrackMenuItem(Icons.delete_outline_rounded, 'Remove from library', () => actions.removeFromLibrary(context, track)),
      ],
    );
  }
}

/// Download state of one song: done check, progress ring, retry/download button.
class DownloadIndicator extends StatelessWidget {
  const DownloadIndicator({super.key, required this.track, this.download, this.onDownload});
  final Track track;
  final Download? download;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final d = download;
    if (track.downloaded || d?.status == 'done' || d?.status == 'skipped') {
      return Tooltip(
        message: 'Downloaded',
        child: Icon(Icons.download_done_rounded, size: 20, color: gx.accent, semanticLabel: 'Downloaded'),
      );
    }
    if (d != null && d.isActive) {
      return Tooltip(
        message: d.status == 'queued' ? 'Waiting…' : 'Downloading ${d.progress.toStringAsFixed(0)}%',
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            value: d.status == 'queued' || d.progress <= 0 ? null : d.progress / 100,
          ),
        ),
      );
    }
    if (onDownload == null) return const SizedBox(width: 20);
    return IconButton(
      tooltip: d?.isFailed == true ? 'Download failed — try again' : 'Download',
      onPressed: onDownload,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        d?.isFailed == true ? Icons.error_outline_rounded : Icons.download_rounded,
        size: 20,
        color: d?.isFailed == true ? Colors.redAccent : gx.muted,
      ),
    );
  }
}
