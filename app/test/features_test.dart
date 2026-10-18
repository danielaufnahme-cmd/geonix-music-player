import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geonix_music_player/models/download.dart';
import 'package:geonix_music_player/models/lyrics.dart';
import 'package:geonix_music_player/models/track.dart';
import 'package:geonix_music_player/screens/downloads_screen.dart';
import 'package:geonix_music_player/state/desktop_theme.dart';
import 'package:geonix_music_player/state/palette.dart';
import 'package:geonix_music_player/state/player_controller.dart';
import 'package:geonix_music_player/theme.dart';
import 'package:geonix_music_player/widgets/lyrics_view.dart';
import 'package:geonix_music_player/widgets/now_playing_panel.dart';

// Trimmed copy of a real ~/.local/state/caelestia/scheme.json.
const _caelestia = '''
{"name": "dynamic", "flavour": "default", "mode": "dark", "variant": "content",
 "colours": {"background": "131315", "onBackground": "e4e2e4", "surface": "131315",
  "surfaceContainerLow": "1b1b1d", "surfaceContainer": "1f1f21", "surfaceContainerHigh": "2a2a2c",
  "onSurface": "e4e2e4", "onSurfaceVariant": "c5c6cd", "outline": "8f9097", "outlineVariant": "44474d",
  "primary": "b4c5ff", "secondary": "c1c6dd", "tertiary": "e1bbdc"}}
''';

void main() {
  group('desktop scheme', () {
    test('parses Caelestia scheme.json', () {
      final s = DesktopScheme.tryParse(_caelestia)!;
      expect(s.brightness, Brightness.dark);
      expect(s.background, const Color(0xFF131315));
      expect(s.surface, const Color(0xFF1F1F21));
      expect(s.surfaceHigh, const Color(0xFF2A2A2C));
      expect(s.primary, const Color(0xFFB4C5FF));
      expect(s.onSurfaceVariant, const Color(0xFFC5C6CD));
      expect(s.outline, const Color(0xFF44474D));
    });

    test('light mode, missing and broken files', () {
      final light = DesktopScheme.tryParse(
          '{"mode":"light","colours":{"background":"#fbf8fd","primary":"445e91","onSurface":"1b1b1f"}}')!;
      expect(light.brightness, Brightness.light);
      expect(light.surface, light.background, reason: 'missing surface keys fall back');
      expect(DesktopScheme.tryParse(''), isNull);
      expect(DesktopScheme.tryParse('{"colours":{"background":"zzz","primary":"445e91","onSurface":"000000"}}'), isNull);
      expect(DesktopScheme.tryParse('[1,2]'), isNull);
    });

    test('theme takes base colors from the desktop, accent from the song', () {
      final s = DesktopScheme.tryParse(_caelestia)!;
      final theme = buildTheme(Brightness.dark, const Color(0xFFE53935), desktop: s);
      final gx = theme.extension<GeonixPalette>()!;
      expect(theme.scaffoldBackgroundColor, s.background);
      expect(gx.surface, s.surface);
      expect(gx.text, s.onSurface);
      // A light-mode theme ignores a dark desktop scheme.
      expect(buildTheme(Brightness.light, kDefaultAccent, desktop: s).scaffoldBackgroundColor, isNot(s.background));
    });

    test('cover accents are pulled toward the desktop hue, at most 25°', () {
      const primary = Color(0xFF3366FF); // blue, hue ~225
      final red = HSLColor.fromColor(const Color(0xFFFF3333)); // hue 0
      final out = HSLColor.fromColor(harmonize(red.toColor(), primary));
      final moved = ((out.hue - red.hue + 540) % 360) - 180;
      expect(moved.abs(), lessThanOrEqualTo(25.01));
      expect(moved, lessThan(0), reason: 'red moves toward blue the short way (through magenta)');
      final near = harmonize(const Color(0xFF3355FF), primary);
      expect((HSLColor.fromColor(near).hue - HSLColor.fromColor(primary).hue).abs(), lessThan(5));
    });

    test('nothing playing on desktop colors uses the desktop primary', () {
      final s = DesktopScheme.tryParse(_caelestia)!;
      expect(desktopPalette(CoverPalette.fallback, s).accent, s.primary);
      final p = desktopPalette(const CoverPalette(accent: Color(0xFFFF8800), deep: Color(0xFF221100)), s);
      expect(p.accent, isNot(s.primary));
    });
  });

  group('lyrics', () {
    final lyrics = Lyrics.fromJson({
      'synced': true,
      'source': 'LRCLIB',
      'lines': [
        {'time_ms': 1000, 'text': 'One'},
        {'time_ms': 5000, 'text': ''},
        {'time_ms': 9000, 'text': 'Three'},
      ],
    });

    test('finds the line being sung', () {
      expect(lyrics.lineAt(Duration.zero), -1);
      expect(lyrics.lineAt(const Duration(milliseconds: 800)), 0, reason: '250 ms lead');
      expect(lyrics.lineAt(const Duration(seconds: 6)), 1);
      expect(lyrics.lineAt(const Duration(minutes: 3)), 2);
    });

    test('plain lyrics never highlight a line', () {
      final plain = Lyrics.fromJson({
        'synced': false,
        'lines': [
          {'time_ms': null, 'text': 'a'},
        ],
      });
      expect(plain.synced, isFalse);
      expect(plain.lineAt(const Duration(seconds: 3)), -1);
    });

    Widget host(List overrides) => ProviderScope(
          overrides: [...overrides],
          child: const MaterialApp(home: Scaffold(body: Center(child: LyricsStrip()))),
        );

    testWidgets('strip shows previous, current and next line', (tester) async {
      await tester.pumpWidget(host([
        currentLyricsProvider.overrideWithValue(AsyncValue.data(lyrics)),
        currentLyricLineProvider.overrideWithValue(1),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('One'), findsOneWidget);
      expect(find.text('♪'), findsOneWidget, reason: 'empty lines show a note');
      expect(find.text('Three'), findsOneWidget);
    });

    testWidgets('strip says when there are no lyrics', (tester) async {
      await tester.pumpWidget(host([currentLyricsProvider.overrideWithValue(const AsyncValue.data(Lyrics.none))]));
      expect(find.text('No lyrics found for this song'), findsOneWidget);
    });
  });

  test('shift-click range selection', () {
    final ids = ['a', 'b', 'c', 'd', 'e'];
    expect(selectRange(ids, 'b', 'd', {}), {'b', 'c', 'd'});
    expect(selectRange(ids, 'd', 'b', {'e'}), {'b', 'c', 'd', 'e'});
    expect(selectRange(ids, 'gone', 'c', {'a'}), {'a', 'c'});
  });

  test('up next "download all" skips downloaded, running and finished songs', () {
    const t = [
      Track(videoId: 'a', title: 'A', downloaded: true),
      Track(videoId: 'b', title: 'B'),
      Track(videoId: 'c', title: 'C'),
      Track(videoId: 'd', title: 'D'),
      Track(videoId: 'e', title: 'E'),
    ];
    final downloads = {
      'c': const Download(id: '1', videoId: 'c', status: 'downloading'),
      'd': const Download(id: '2', videoId: 'd', status: 'done'),
      'e': const Download(id: '3', videoId: 'e', status: 'failed'),
    };
    expect(notDownloaded(t, downloads).map((x) => x.videoId), ['b', 'e']);
  });
}
