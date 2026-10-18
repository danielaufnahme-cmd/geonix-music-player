import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../theme.dart';
import 'playlist_import.dart';

export 'playlist_import.dart';

/// What the user chose in the "New playlist" dialog. [importUrl] is set when
/// the playlist should be filled from a YouTube Music playlist.
class NewPlaylistRequest {
  const NewPlaylistRequest({required this.name, this.importUrl});
  final String name;
  final String? importUrl;
}

/// "New playlist" dialog with an optional "Import from YouTube Music" section
/// that previews the playlist and shows which songs are already downloaded.
Future<NewPlaylistRequest?> showNewPlaylistDialog(
  BuildContext context, {
  required Future<PlaylistPreview> Function(String url) loadPreview,
  bool allowImport = true,
}) {
  return showDialog<NewPlaylistRequest>(
    context: context,
    builder: (context) => _NewPlaylistDialog(loadPreview: loadPreview, allowImport: allowImport),
  );
}

class _NewPlaylistDialog extends StatefulWidget {
  const _NewPlaylistDialog({required this.loadPreview, required this.allowImport});
  final Future<PlaylistPreview> Function(String url) loadPreview;
  final bool allowImport;

  @override
  State<_NewPlaylistDialog> createState() => _NewPlaylistDialogState();
}

class _NewPlaylistDialogState extends State<_NewPlaylistDialog> {
  final _name = TextEditingController();
  bool _import = false;
  bool _nameEdited = false;
  PlaylistPreview? _preview;
  String _url = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _onPreview(PlaylistPreview? preview, String url) {
    setState(() {
      _preview = preview;
      _url = url;
      if (preview != null && (!_nameEdited || _name.text.trim().isEmpty)) {
        _name.text = preview.title;
        _nameEdited = false;
      }
    });
  }

  bool get _canCreate => _import ? _preview != null : _name.text.trim().isNotEmpty;

  void _submit() {
    if (!_canCreate) return;
    final name = _name.text.trim().isNotEmpty ? _name.text.trim() : (_preview?.title ?? '');
    Navigator.pop(context, NewPlaylistRequest(name: name, importUrl: _import ? _url : null));
  }

  String get _createLabel {
    if (!_import || _preview == null) return 'Create';
    final missing = ImportCounts(_preview!, null).willDownload;
    return missing == 0 ? 'Create playlist' : 'Create & download $missing';
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('New playlist'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: _import ? 'Uses the YouTube playlist name if empty' : 'My playlist',
                counterText: '',
              ),
              onChanged: (_) => setState(() => _nameEdited = true),
              onSubmitted: (_) => _submit(),
            ),
            if (widget.allowImport) ...[
              const SizedBox(height: 12),
              Material(
                color: _import ? gx.accentSoft : gx.surfaceHigh.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                child: SwitchListTile(
                  key: const Key('import-switch'),
                  value: _import,
                  onChanged: (v) => setState(() => _import = v),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  secondary: Icon(Icons.playlist_add_rounded, color: _import ? gx.accent : gx.muted),
                  title: const Text('Import from YouTube Music'),
                  subtitle: Text('Paste a playlist or album link. Missing songs download automatically.',
                      style: text.bodySmall?.copyWith(color: gx.muted)),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _import
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: PlaylistImportField(loadPreview: widget.loadPreview, onPreview: _onPreview),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          key: const Key('create-playlist'),
          onPressed: _canCreate ? _submit : null,
          icon: Icon(_import ? Icons.download_rounded : Icons.add_rounded),
          label: Text(_createLabel),
        ),
      ],
    );
  }
}
