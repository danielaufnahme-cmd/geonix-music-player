import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../theme.dart';
import 'playlist_cover.dart';

Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String confirm = 'OK',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: InputDecoration(hintText: hint, counterText: ''),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(confirm)),
      ],
    ),
  ).whenComplete(controller.dispose);
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Confirm',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 380, child: Text(message)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(confirm)),
      ],
    ),
  );
  return ok ?? false;
}

/// Returns null (cancel), false (keep file) or true (also delete the file).
Future<bool?> showRemoveTrackDialog(BuildContext context, Track track) {
  var deleteFile = false;
  return showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Remove from library?'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('“${track.title}” will be removed from your library and all playlists.'),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: deleteFile,
              onChanged: (v) => setState(() => deleteFile = v ?? false),
              title: const Text('Also delete the MP3 file from disk'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, deleteFile), child: const Text('Remove')),
        ],
      ),
    ),
  );
}

/// Pick a playlist; a returned playlist with id -1 means "create new".
Future<Playlist?> showPlaylistPicker(BuildContext context, List<Playlist> playlists) {
  final gx = context.gx;
  return showDialog<Playlist>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add to playlist'),
      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      content: SizedBox(
        width: 400,
        height: 360,
        child: ListView(children: [
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: gx.accentSoft, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.add_rounded, color: gx.accent),
            ),
            title: const Text('New playlist'),
            onTap: () => Navigator.pop(context, const Playlist(id: -1, name: '')),
          ),
          for (final p in playlists)
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: PlaylistCover(trackIds: p.coverTrackIds, size: 44, radius: 10),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${p.trackCount} songs', style: TextStyle(color: gx.muted)),
              onTap: () => Navigator.pop(context, p),
            ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    ),
  );
}
