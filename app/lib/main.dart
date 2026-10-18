import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/shell.dart';
import 'state/desktop_theme.dart';
import 'state/player_controller.dart';
import 'state/providers.dart';
import 'theme.dart';
import 'util/perf.dart';
import 'widgets/waves.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  Perf.start();
  runApp(const ProviderScope(child: GeonixApp()));
}

class GeonixApp extends ConsumerWidget {
  const GeonixApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The accent follows the playing song's cover; MaterialApp animates
    // theme changes, so colors fade instead of jumping.
    final accent = ref.watch(accentProvider);
    final desktop = ref.watch(activeDesktopSchemeProvider);
    return MaterialApp(
      title: 'Music Player',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: ref.watch(messengerKeyProvider),
      themeMode: ref.watch(effectiveThemeModeProvider),
      theme: buildTheme(Brightness.light, accent, desktop: desktop),
      darkTheme: buildTheme(Brightness.dark, accent, desktop: desktop),
      themeAnimationDuration: const Duration(milliseconds: 700),
      themeAnimationCurve: Curves.easeOutCubic,
      // One shared wave clock for every screen and route (lively while playing).
      builder: (context, child) => Consumer(
        builder: (context, ref, _) =>
            WaveClockScope(playing: ref.watch(playerProvider.select((s) => s.playing)), child: child!),
      ),
      home: const Shell(),
    );
  }
}
