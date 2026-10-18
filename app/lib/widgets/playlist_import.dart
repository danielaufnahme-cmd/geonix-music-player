import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/client.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../state/providers.dart' show looksLikePlaylistUrl;
import '../theme.dart';
import '../util/format.dart';
import 'cover_image.dart';
import 'skeleton.dart';

const kInLibraryGreen = Color(0xFF2FBF71);

/// Turns backend/worker errors into something a person can act on.
String friendlyImportError(Object error) {
  final msg = error.toString();
  final lower = msg.toLowerCase();
  if (error is ApiException && error.isOffline) return 'Can’t reach the Geonix backend. Is it running?';
  if (lower.contains('private') || lower.contains('does not exist') || lower.contains('not found') ||
      lower.contains('unavailable') || lower.contains('http error 4') || lower.contains('unable to download')) {
    return 'This playlist is private, deleted or doesn’t exist. Make sure it’s public or unlisted.';
  }
  if (lower.contains('no available songs')) return 'That playlist has no songs that can be downloaded.';
  if (lower.contains('list=')) return 'That doesn’t look like a playlist link. It should contain “list=”.';
  return 'Couldn’t load that playlist: $msg';
}

/// What happens to one song of an imported playlist.
enum ImportStatus { inPlaylist, inLibrary, willDownload }

ImportStatus importStatusOf(Track t, Set<String>? existingIds) {
  if (existingIds != null && existingIds.contains(t.videoId)) return ImportStatus.inPlaylist;
  return t.downloaded ? ImportStatus.inLibrary : ImportStatus.willDownload;
}

/// Per-status counts for a preview. [existingIds] are the songs already in
/// the target playlist (null when creating a new playlist).
class ImportCounts {
  ImportCounts(PlaylistPreview p, Set<String>? existingIds) {
    final seen = <String>{};
    for (final t in p.tracks) {
      if (!seen.add(t.videoId)) continue;
      switch (importStatusOf(t, existingIds)) {
        case ImportStatus.inPlaylist:
          inPlaylist++;
        case ImportStatus.inLibrary:
          inLibrary++;
        case ImportStatus.willDownload:
          willDownload++;
      }
    }
    total = p.tracks.length;
  }

  int total = 0;
  int inPlaylist = 0;
  int inLibrary = 0;
  int willDownload = 0;

  /// Songs that will be added to the playlist.
  int get toAdd => inLibrary + willDownload;
}

/// Link field + live preview for importing a YouTube Music playlist. Reports
/// the loaded preview (or null while empty, loading or invalid) to [onPreview].
class PlaylistImportField extends StatefulWidget {
  const PlaylistImportField({
    super.key,
    required this.loadPreview,
    required this.onPreview,
    this.existingIds,
    this.autofocus = false,
  });

  final Future<PlaylistPreview> Function(String url) loadPreview;
  final void Function(PlaylistPreview? preview, String url) onPreview;
  final Set<String>? existingIds;
  final bool autofocus;

  @override
  State<PlaylistImportField> createState() => _PlaylistImportFieldState();
}

class _PlaylistImportFieldState extends State<PlaylistImportField> {
  final _url = TextEditingController();
  Timer? _debounce;

  /// The URL the current preview/request belongs to (guards against stale replies).
  String _requested = '';
  bool _loading = false;
  String? _error;
  PlaylistPreview? _preview;

  @override
  void dispose() {
    _debounce?.cancel();
    _url.dispose();
    super.dispose();
  }

  void _onUrlChanged(String value) {
    _debounce?.cancel();
    final url = value.trim();
    final valid = url.isNotEmpty && looksLikePlaylistUrl(url);
    setState(() {
      _preview = null;
      _requested = url;
      _loading = valid;
      _error = url.isEmpty || valid ? null : 'That doesn’t look like a playlist link. It should contain “list=”.';
    });
    widget.onPreview(null, url);
    if (valid) _debounce = Timer(const Duration(milliseconds: 500), () => _fetch(url));
  }

  Future<void> _fetch(String url) async {
    try {
      final preview = await widget.loadPreview(url);
      if (!mounted || url != _requested) return;
      final empty = preview.tracks.isEmpty;
      setState(() {
        _preview = preview;
        _loading = false;
        _error = empty ? 'That playlist has no songs that can be downloaded.' : null;
      });
      widget.onPreview(empty ? null : preview, url);
    } on Object catch (e) {
      if (!mounted || url != _requested) return;
      setState(() {
        _loading = false;
        _error = friendlyImportError(e);
      });
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    _url.text = text;
    _onUrlChanged(text);
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        key: const Key('import-url'),
        controller: _url,
        autofocus: widget.autofocus,
        onChanged: _onUrlChanged,
        decoration: InputDecoration(
          labelText: 'YouTube Music playlist link',
          hintText: 'https://music.youtube.com/playlist?list=…',
          prefixIcon: const Icon(Icons.link_rounded),
          suffixIcon: IconButton(tooltip: 'Paste', onPressed: _paste, icon: const Icon(Icons.content_paste_rounded)),
        ),
      ),
      const SizedBox(height: 14),
      if (_loading)
        const _PreviewSkeleton()
      else if (_error != null)
        _ErrorNote(message: _error!)
      else if (_preview != null)
        PlaylistImportPreviewList(preview: _preview!, existingIds: widget.existingIds)
      else
        Text(
          widget.existingIds == null
              ? 'Songs you already have are added right away. Only the rest is downloaded.'
              : 'Songs already in this playlist are skipped, songs you have are added right away, '
                  'only the rest is downloaded.',
          style: text.bodySmall?.copyWith(color: gx.muted),
        ),
    ]);
  }
}

/// Summary plus the song list of a playlist preview, marking each song as
/// "Already in this playlist", "In library" or "Will download".
class PlaylistImportPreviewList extends StatelessWidget {
  const PlaylistImportPreviewList({
    super.key,
    required this.preview,
    this.existingIds,
    this.showCovers = true,
    this.maxHeight = 280,
  });

  final PlaylistPreview preview;

  /// Songs already in the target playlist; null when creating a new playlist.
  final Set<String>? existingIds;
  final bool showCovers;
  final double maxHeight;

  static String summary(PlaylistPreview p, [Set<String>? existingIds]) {
    final c = ImportCounts(p, existingIds);
    return [
      plural(c.total, 'song'),
      if (existingIds != null) '${c.inPlaylist} already in this playlist',
      '${c.inLibrary} ${existingIds == null ? 'already ' : ''}in library',
      '${c.willDownload} to download',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final tracks = preview.tracks;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.queue_music_rounded, size: 18, color: gx.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(summary(preview, existingIds),
              key: const Key('import-summary'), style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 10),
      Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: gx.surfaceHigh.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: gx.outline),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final t = tracks[i];
            final status = importStatusOf(t, existingIds);
            return Opacity(
              opacity: status == ImportStatus.inPlaylist ? 0.55 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(children: [
                  SizedBox(
                    width: 26,
                    child:
                        Text('${i + 1}', textAlign: TextAlign.right, style: text.bodySmall?.copyWith(color: gx.muted)),
                  ),
                  const SizedBox(width: 10),
                  if (showCovers) ...[
                    CoverImage(videoId: t.videoId, size: 36, radius: 6),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                      Text(t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: gx.muted)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  ImportStatusChip(status: status),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class ImportStatusChip extends StatelessWidget {
  const ImportStatusChip({super.key, required this.status});
  final ImportStatus status;

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final (color, icon, label) = switch (status) {
      ImportStatus.inPlaylist => (gx.accent, Icons.playlist_add_check_rounded, 'Already in this playlist'),
      ImportStatus.inLibrary => (kInLibraryGreen, Icons.check_circle_rounded, 'In library'),
      ImportStatus.willDownload => (gx.muted, Icons.download_rounded, 'Will download'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: status == ImportStatus.willDownload ? 0.10 : 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// "Import from YouTube Music" into an existing playlist. Returns the
/// playlist link to import, or null when cancelled.
Future<String?> showImportIntoPlaylistDialog(
  BuildContext context, {
  required String playlistName,
  required Set<String> existingIds,
  required Future<PlaylistPreview> Function(String url) loadPreview,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _ImportIntoPlaylistDialog(playlistName: playlistName, existingIds: existingIds, loadPreview: loadPreview),
  );
}

class _ImportIntoPlaylistDialog extends StatefulWidget {
  const _ImportIntoPlaylistDialog({required this.playlistName, required this.existingIds, required this.loadPreview});
  final String playlistName;
  final Set<String> existingIds;
  final Future<PlaylistPreview> Function(String url) loadPreview;

  @override
  State<_ImportIntoPlaylistDialog> createState() => _ImportIntoPlaylistDialogState();
}

class _ImportIntoPlaylistDialogState extends State<_ImportIntoPlaylistDialog> {
  PlaylistPreview? _preview;
  String _url = '';

  ImportCounts? get _counts => _preview == null ? null : ImportCounts(_preview!, widget.existingIds);

  String get _label {
    final c = _counts;
    if (c == null) return 'Add songs';
    if (c.toAdd == 0) return 'Nothing new to add';
    return c.willDownload == 0 ? 'Add ${plural(c.toAdd, 'song')}' : 'Add & download ${c.willDownload}';
  }

  @override
  Widget build(BuildContext context) {
    final c = _counts;
    final canAdd = c != null && c.toAdd > 0;
    return AlertDialog(
      title: Text('Import into “${widget.playlistName}”', maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: PlaylistImportField(
            autofocus: true,
            existingIds: widget.existingIds,
            loadPreview: widget.loadPreview,
            onPreview: (preview, url) => setState(() {
              _preview = preview;
              _url = url;
            }),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          key: const Key('import-into-playlist'),
          onPressed: canAdd ? () => Navigator.pop(context, _url) : null,
          icon: Icon(c != null && c.willDownload > 0 ? Icons.download_rounded : Icons.playlist_add_rounded),
          label: Text(_label),
        ),
      ],
    );
  }
}

class _PreviewSkeleton extends StatelessWidget {
  const _PreviewSkeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SkeletonBox(width: 260, height: 16),
          const SizedBox(height: 12),
          for (var i = 0; i < 4; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SkeletonBox(width: 36, height: 36, radius: 6),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(height: 14)),
                SizedBox(width: 40),
                SkeletonBox(width: 80, height: 20, radius: 999),
              ]),
            ),
        ]),
      );
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: error.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded, size: 18, color: error),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: TextStyle(color: error))),
      ]),
    );
  }
}
