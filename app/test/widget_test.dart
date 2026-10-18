import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geonix_music_player/models/download.dart';
import 'package:geonix_music_player/models/playlist.dart';
import 'package:geonix_music_player/models/track.dart';
import 'package:geonix_music_player/state/palette.dart';
import 'package:geonix_music_player/util/format.dart';
import 'package:geonix_music_player/widgets/empty_state.dart';
import 'package:geonix_music_player/widgets/new_playlist_dialog.dart';
import 'package:geonix_music_player/widgets/track_tile.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: Scaffold(body: SizedBox(width: 1200, child: child)),
    );

const _track = Track(
  videoId: 'wU26xVT_vBU',
  title: 'One More Time',
  artist: 'Daft Punk',
  album: 'Discovery',
  durationSec: 320,
);

void main() {
  testWidgets('TrackTile shows song info and reacts to taps', (tester) async {
    var taps = 0;
    var downloads = 0;
    await tester.pumpWidget(_host(TrackTile(
      track: _track,
      index: 0,
      showCover: false,
      onTap: () => taps++,
      onDownload: () => downloads++,
    )));

    expect(find.text('One More Time'), findsOneWidget);
    expect(find.text('Daft Punk'), findsOneWidget);
    expect(find.text('Discovery'), findsOneWidget);
    expect(find.text('5:20'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.text('One More Time'));
    await tester.tap(find.byTooltip('Download'));
    expect(taps, 1);
    expect(downloads, 1);
  });

  testWidgets('TrackTile shows download progress and finished state', (tester) async {
    await tester.pumpWidget(_host(const TrackTile(
      track: _track,
      showCover: false,
      download: Download(id: 'd1', videoId: 'wU26xVT_vBU', status: 'downloading', progress: 40),
    )));
    final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
    expect(ring.value, closeTo(0.4, 1e-9));

    await tester.pumpWidget(_host(TrackTile(track: _track.copyWith(downloaded: true), showCover: false)));
    expect(find.bySemanticsLabel('Downloaded'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('EmptyState shows its message and action', (tester) async {
    var pressed = false;
    await tester.pumpWidget(_host(EmptyState(
      icon: Icons.library_music_rounded,
      title: 'Your library is empty',
      message: 'Search for a song to get started.',
      actionLabel: 'Search music',
      onAction: () => pressed = true,
    )));
    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('Search for a song to get started.'), findsOneWidget);
    await tester.tap(find.text('Search music'));
    expect(pressed, isTrue);
  });

  test('formatDuration and formatTotal', () {
    expect(formatDuration(const Duration(seconds: 65)), '1:05');
    expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(formatDuration(const Duration(seconds: -4)), '0:00');
    expect(formatTotal(4320), '1 hr 12 min');
    expect(plural(1, 'song'), '1 song');
    expect(plural(3, 'song'), '3 songs');
  });

  test('palette picks the vivid color and ignores greys', () {
    Uint8List pixels(List<List<int>> colors, int each) => Uint8List.fromList([
          for (final c in colors)
            for (var i = 0; i < each; i++) ...[c[0], c[1], c[2], 255],
        ]);

    // Mostly grey cover with a strong red area.
    final p = paletteFromPixels(pixels([
      [128, 128, 128],
      [220, 30, 40],
    ], 200));
    final hsl = HSLColor.fromColor(p.accent);
    expect(hsl.hue < 15 || hsl.hue > 345, isTrue, reason: 'accent should be red, got ${hsl.hue}');
    expect(HSLColor.fromColor(p.deep).lightness, lessThan(0.2));

    // Pure greyscale keeps the default accent.
    final grey = paletteFromPixels(pixels([
      [40, 40, 40],
      [200, 200, 200],
    ], 100));
    expect(grey.accent, CoverPalette.fallback.accent);
  });

  const preview = PlaylistPreview(title: 'Alive 2007', tracks: [
    Track(videoId: 'a1', title: 'Robot Rock', artist: 'Daft Punk', downloaded: true),
    Track(videoId: 'a2', title: 'Touch It', artist: 'Daft Punk'),
    Track(videoId: 'a3', title: 'Television Rules the Nation', artist: 'Daft Punk'),
  ]);

  testWidgets('import preview marks songs in library vs to download', (tester) async {
    await tester.pumpWidget(_host(const PlaylistImportPreviewList(preview: preview, showCovers: false)));
    expect(find.text('3 songs · 1 already in library · 2 to download'), findsOneWidget);
    expect(find.text('In library'), findsOneWidget);
    expect(find.text('Will download'), findsNWidgets(2));
    expect(find.text('Robot Rock'), findsOneWidget);
  });

  testWidgets('import into an existing playlist marks songs already there', (tester) async {
    await tester.pumpWidget(_host(const PlaylistImportPreviewList(
      preview: preview,
      existingIds: {'a2'},
      showCovers: false,
    )));
    expect(find.text('3 songs · 1 already in this playlist · 1 in library · 1 to download'), findsOneWidget);
    expect(find.text('Already in this playlist'), findsOneWidget);
    expect(find.text('In library'), findsOneWidget);
    expect(find.text('Will download'), findsOneWidget);
  });

  testWidgets('import-into-playlist dialog returns the link and labels the button', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showImportIntoPlaylistDialog(
              context,
              playlistName: 'smal',
              existingIds: {'a1', 'a2', 'a3'},
              loadPreview: (url) async => preview,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Import into “smal”'), findsOneWidget);

    const url = 'https://music.youtube.com/playlist?list=OLAK5uy_test';
    await tester.enterText(find.byKey(const Key('import-url')), url);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    // Every song is already in the playlist: nothing to add.
    expect(find.text('Nothing new to add'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-into-playlist')));
    await tester.pumpAndSettle();
    expect(result, 'unset');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);

    // With an empty target playlist the button adds & downloads.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showImportIntoPlaylistDialog(
              context,
              playlistName: 'smal',
              existingIds: const {},
              loadPreview: (url) async => preview,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('import-url')), url);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Add & download 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-into-playlist')));
    await tester.pumpAndSettle();
    expect(result, url);
  });

  testWidgets('new playlist dialog imports from a YouTube Music link', (tester) async {
    final requested = <String>[];
    NewPlaylistRequest? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showNewPlaylistDialog(context, loadPreview: (url) async {
              requested.add(url);
              return preview;
            }),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Without a name the plain "Create" button is disabled.
    ButtonStyleButton create() => tester.widget<ButtonStyleButton>(find.byKey(const Key('create-playlist')));
    expect(create().onPressed, isNull);

    await tester.tap(find.byKey(const Key('import-switch')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('import-url')), 'not a link');
    await tester.pump();
    expect(find.textContaining('doesn’t look like a playlist link'), findsOneWidget);

    const url = 'https://music.youtube.com/playlist?list=OLAK5uy_test';
    await tester.enterText(find.byKey(const Key('import-url')), url);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(requested, [url]);
    expect(find.text('3 songs · 1 already in library · 2 to download'), findsOneWidget);
    expect(find.text('Alive 2007'), findsOneWidget, reason: 'name is prefilled from the YouTube title');
    expect(find.text('Create & download 2'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Road trip');
    await tester.pump();
    await tester.tap(find.text('Create & download 2'));
    await tester.pumpAndSettle();
    expect(result?.name, 'Road trip');
    expect(result?.importUrl, url);
  });

  test('import errors are explained in plain words', () {
    expect(friendlyImportError(Exception('ERROR: [youtube:tab] PLx: Unable to download API page: HTTP Error 400')),
        contains('private, deleted'));
    expect(friendlyImportError(Exception('that playlist has no available songs')), contains('no songs'));
  });
}
