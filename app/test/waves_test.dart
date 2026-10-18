import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geonix_music_player/widgets/waves.dart';

const _accent = Color(0xFF8B7CFF);
const _deep = Color(0xFF1A1730);

Future<void> _frames(WidgetTester tester, Duration total, {Duration step = const Duration(milliseconds: 100)}) async {
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

void main() {
  testWidgets('wave, aurora and seek painters render without errors', (tester) async {
    late WaveClock clock;
    final colors = WaveColors.from(accent: _accent, deep: _deep, brightness: Brightness.dark);
    await tester.pumpWidget(MaterialApp(
      home: WaveClockScope(
        playing: true,
        child: Builder(builder: (context) {
          clock = context.waveClock;
          return Column(children: [
            Expanded(
              child: CustomPaint(
                painter: AuroraPainter(clock: clock, base: colors.base, colors: colors.aurora, vignette: 0.5),
                foregroundPainter: WaveLayersPainter(clock: clock, colors: colors.layers, glow: true),
                child: const SizedBox.expand(),
              ),
            ),
            SizedBox(
              height: 34,
              width: 400,
              child: CustomPaint(
                painter: WavySeekPainter(
                  clock: clock,
                  fraction: 0.4,
                  active: _accent,
                  inactive: Colors.white24,
                  large: true,
                ),
              ),
            ),
            const SizedBox(width: 10, height: 10, child: CustomPaint()),
          ]);
        }),
      ),
    ));
    final phase0 = clock.phase;
    await _frames(tester, const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(clock.phase, greaterThan(phase0), reason: 'waves move while playing');
    expect(clock.energy, greaterThan(0.9), reason: 'energy eases up to lively');

    // Degenerate sizes must not throw either.
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    WaveLayersPainter(clock: clock, colors: colors.layers).paint(canvas, Size.zero);
    WavySeekPainter(clock: clock, fraction: 2, active: _accent, inactive: Colors.grey).paint(canvas, const Size(5, 5));
    recorder.endRecording();
  });

  testWidgets('WaveBackground works in both themes and the clock calms down, then stops', (tester) async {
    Widget app({required bool playing, required Brightness brightness}) => MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: WaveClockScope(
            playing: playing,
            child: Builder(
              builder: (context) => Scaffold(
                body: WaveBackground(
                  accent: _accent,
                  deep: _deep,
                  intensity: 0.4,
                  child: Center(child: Text(context.waveClock.isTicking ? 'ticking' : 'idle')),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(app(playing: true, brightness: Brightness.light));
    await _frames(tester, const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.byType(WaveBackground), findsOneWidget);

    final clock = tester.element(find.byType(WaveBackground)).waveClock;
    expect(clock.isTicking, isTrue);

    // Pause: energy eases down smoothly (no jump), then the ticker stops.
    await tester.pumpWidget(app(playing: false, brightness: Brightness.dark));
    await tester.pump(const Duration(milliseconds: 100));
    expect(clock.energy, inExclusiveRange(0.5, 1.0), reason: 'calms down gradually');
    await _frames(tester, const Duration(seconds: 12));
    expect(clock.energy, 0);
    expect(clock.isTicking, isFalse, reason: 'no frames when idle');
    final frozen = clock.phase;
    await _frames(tester, const Duration(seconds: 1));
    expect(clock.phase, frozen);

    // Playing again wakes it up.
    await tester.pumpWidget(app(playing: true, brightness: Brightness.dark));
    await _frames(tester, const Duration(milliseconds: 500));
    expect(clock.isTicking, isTrue);
    expect(clock.phase, greaterThan(frozen));
    expect(tester.takeException(), isNull);
  });

  testWidgets('breathing glow uses a cached mask and background layers repaint at half rate', (tester) async {
    late WaveClock clock;
    await tester.pumpWidget(MaterialApp(
      home: WaveClockScope(
        playing: true,
        child: Builder(builder: (context) {
          clock = context.waveClock;
          return const Center(
            child: BreathingGlow(color: _accent, radius: 28, child: SizedBox(width: 200, height: 200)),
          );
        }),
      ),
    ));
    var full = 0, half = 0;
    clock.addListener(() => full++);
    clock.halfRate.addListener(() => half++);
    await _frames(tester, const Duration(seconds: 1), step: const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
    expect(full, greaterThan(40));
    expect(half, inInclusiveRange(full ~/ 2 - 1, full ~/ 2 + 1), reason: '~30 fps for calm backgrounds');
  });

  test('wave colors are translucent and differ between light and dark', () {
    final dark = WaveColors.from(accent: _accent, deep: _deep, brightness: Brightness.dark);
    final light = WaveColors.from(accent: _accent, deep: _deep, brightness: Brightness.light);
    for (final c in [...dark.layers, ...light.layers]) {
      expect(c.a, lessThan(0.5), reason: 'text must stay readable over the waves');
    }
    expect(dark.base.computeLuminance(), lessThan(light.base.computeLuminance()));
  });
}
