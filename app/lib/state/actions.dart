import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../util/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/new_playlist_dialog.dart';
import 'providers.dart';

/// User actions shared by several screens. Each one updates the backend,
/// refreshes the affected views and reports the outcome in a snackbar.
class LibraryActions {
  LibraryActions(this.ref);
  final WidgetRef ref;

  void _msg(String text) => ref.read(messengerKeyProvider).currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> download(Track track) => ref.read(downloadsProvider.notifier).download(track);

  Future<void> downloadAll(Iterable<Track> tracks) async {
    final todo = tracks.where((t) => !t.downloaded).toList();
    if (todo.isEmpty) {
      _msg('Everything here is already downloaded');
      return;
    }
    for (final t in todo) {
      await ref.read(downloadsProvider.notifier).download(t);
    }
    _msg('Downloading ${todo.length} song${todo.length == 1 ? '' : 's'}');
  }

  /// Shows the "New playlist" dialog. With the import section checked, the
  /// playlist is filled from YouTube Music and missing songs are downloaded.
  Future<Playlist?> createPlaylist(BuildContext context, {bool allowImport = true}) async {
    final api = ref.read(apiProvider);
    final request = await showNewPlaylistDialog(context, loadPreview: api.playlistInfo, allowImport: allowImport);
    if (request == null) return null;
    final url = request.importUrl;
    try {
      if (url == null) {
        if (request.name.isEmpty) return null;
        final p = await api.createPlaylist(request.name);
        ref.invalidate(playlistsProvider);
        return p;
      }
      final r = await api.downloadPlaylist(url, name: request.name);
      ref.invalidate(playlistsProvider);
      ref.invalidate(playlistProvider(r.playlistId));
      _msg(r.queued == 0
          ? 'Created “${request.name}”. Every song was already in your library'
          : 'Created “${request.name}”. Downloading ${plural(r.queued, 'song')}'
              '${r.skipped > 0 ? ' (${r.skipped} already in library)' : ''}');
      return Playlist(id: r.playlistId, name: request.name, kind: 'imported');
    } on Exception catch (e) {
      _msg(url == null ? 'Could not create playlist: $e' : friendlyImportError(e));
      return null;
    }
  }

  /// "Import from YouTube Music" into an existing playlist: previews the
  /// songs, appends the new ones and downloads only those not in the library.
  Future<void> importIntoPlaylist(BuildContext context, Playlist playlist) async {
    final api = ref.read(apiProvider);
    final url = await showImportIntoPlaylistDialog(
      context,
      playlistName: playlist.name,
      existingIds: {for (final t in playlist.tracks) t.videoId},
      loadPreview: api.playlistInfo,
    );
    if (url == null) return;
    try {
      final r = await api.downloadPlaylist(url, playlistId: playlist.id);
      ref.invalidate(playlistsProvider);
      ref.invalidate(playlistProvider(playlist.id));
      final added = r.queued + r.skipped;
      _msg(added == 0
          ? 'Nothing new — every song is already in “${playlist.name}”'
          : 'Added ${plural(added, 'song')} to “${playlist.name}”'
              '${r.queued > 0 ? ', downloading ${r.queued}' : ''}'
              '${r.alreadyInPlaylist > 0 ? ' (${r.alreadyInPlaylist} already there)' : ''}');
    } on Exception catch (e) {
      _msg(friendlyImportError(e));
    }
  }

  Future<void> addToPlaylist(BuildContext context, Track track) async {
    final playlists = (await ref.read(playlistsProvider.future)).where((p) => !p.isDiscover).toList();
    if (!context.mounted) return;
    final choice = await showPlaylistPicker(context, playlists);
    if (choice == null || !context.mounted) return;
    final target = choice.id < 0 ? await createPlaylist(context, allowImport: false) : choice;
    if (target == null) return;
    try {
      await ref.read(apiProvider).addToPlaylist(target.id, track.videoId);
      ref.invalidate(playlistsProvider);
      ref.invalidate(playlistProvider(target.id));
      _msg('Added to “${target.name}”');
    } on Exception catch (e) {
      _msg('Could not add: $e');
    }
  }

  Future<void> removeFromPlaylist(Playlist playlist, Track track) async {
    try {
      await ref.read(apiProvider).removeFromPlaylist(playlist.id, track.videoId);
      ref.invalidate(playlistsProvider);
      ref.invalidate(playlistProvider(playlist.id));
    } on Exception catch (e) {
      _msg('Could not remove: $e');
    }
  }

  Future<void> removeFromLibrary(BuildContext context, Track track) async {
    final deleteFile = await showRemoveTrackDialog(context, track);
    if (deleteFile == null) return;
    try {
      await ref.read(apiProvider).deleteTrack(track.videoId, deleteFile: deleteFile);
      refreshLibrary(ref.invalidate);
      _msg(deleteFile ? 'Removed and deleted the file' : 'Removed from your library');
    } on Exception catch (e) {
      _msg('Could not remove: $e');
    }
  }

  Future<void> renamePlaylist(BuildContext context, Playlist playlist) async {
    final name = await showTextInputDialog(context,
        title: 'Rename playlist', initial: playlist.name, confirm: 'Save', hint: 'Playlist name');
    if (name == null || name.trim().isEmpty || name.trim() == playlist.name) return;
    try {
      await ref.read(apiProvider).renamePlaylist(playlist.id, name.trim());
      ref.invalidate(playlistsProvider);
      ref.invalidate(playlistProvider(playlist.id));
    } on Exception catch (e) {
      _msg('Could not rename: $e');
    }
  }

  /// Returns true when the playlist was deleted.
  Future<bool> deletePlaylist(BuildContext context, Playlist playlist) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete “${playlist.name}”?',
      message: 'The playlist is removed. Your songs and music files stay in your library.',
      confirm: 'Delete playlist',
    );
    if (!ok) return false;
    try {
      await ref.read(apiProvider).deletePlaylist(playlist.id);
      ref.invalidate(playlistsProvider);
      _msg('Deleted “${playlist.name}”');
      return true;
    } on Exception catch (e) {
      _msg('Could not delete: $e');
      return false;
    }
  }

  Future<int?> importPlaylist(String url) async {
    try {
      final r = await ref.read(apiProvider).downloadPlaylist(url);
      ref.invalidate(playlistsProvider);
      _msg(r.queued == 0
          ? 'Playlist imported — every song was already downloaded'
          : 'Importing playlist: downloading ${r.queued} song${r.queued == 1 ? '' : 's'}'
              '${r.skipped > 0 ? ' (${r.skipped} already in library)' : ''}');
      return r.playlistId;
    } on Exception catch (e) {
      _msg('Import failed: $e');
      return null;
    }
  }
}
