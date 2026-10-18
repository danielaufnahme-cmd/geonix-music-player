import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Dev-only frame timing log, enabled with `--dart-define=GEONIX_PERF=true`.
const bool kPerf = bool.fromEnvironment('GEONIX_PERF');

/// With GEONIX_PERF: run the scripted measurement (play, open Now Playing,
/// close it) and quit. Value = seconds to stay on Now Playing; 0 = off.
const int kPerfAutoSeconds = int.fromEnvironment('GEONIX_PERF_AUTO_SECONDS');

/// Collects [FrameTiming]s per named phase and prints a summary line
/// (frame count, average / p90 / max build and raster time, janky frames).
class Perf {
  Perf._();

  static String _phase = 'startup';
  static final List<FrameTiming> _frames = [];
  static final Stopwatch _clock = Stopwatch();
  static bool _started = false;

  static void start() {
    if (!kPerf || _started) return;
    _started = true;
    _clock.start();
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
    _log('perf: monitoring frame timings');
  }

  /// End the current phase (printing its stats) and begin [name].
  static void phase(String name) {
    if (!kPerf) return;
    _report();
    _phase = name;
    _clock
      ..reset()
      ..start();
  }

  static void _report() {
    final seconds = _clock.elapsedMilliseconds / 1000;
    if (_frames.isEmpty) {
      _log('perf[$_phase] ${seconds.toStringAsFixed(1)}s: 0 frames');
      return;
    }
    double ms(Duration d) => d.inMicroseconds / 1000;
    final build = _frames.map((f) => ms(f.buildDuration)).toList()..sort();
    final raster = _frames.map((f) => ms(f.rasterDuration)).toList()..sort();
    final total = _frames.map((f) => ms(f.totalSpan)).toList()..sort();
    String stats(List<double> v) {
      final avg = v.reduce((a, b) => a + b) / v.length;
      final p90 = v[((v.length - 1) * 0.9).round()];
      return 'avg ${avg.toStringAsFixed(1)} p90 ${p90.toStringAsFixed(1)} max ${v.last.toStringAsFixed(1)}';
    }

    final janky = total.where((t) => t > 16.7).length;
    _log('perf[$_phase] ${seconds.toStringAsFixed(1)}s: ${_frames.length} frames '
        '(${(_frames.length / (seconds == 0 ? 1 : seconds)).toStringAsFixed(0)} fps) | '
        'build ${stats(build)} | raster ${stats(raster)} | total ${stats(total)} | janky >16.7ms: $janky');
    _frames.clear();
  }

  static void _log(String line) {
    // stdout so it lands in launch logs even in profile/release builds.
    stdout.writeln(line);
    if (kDebugMode) debugPrint(line);
  }

  static Future<void> finishAndExit() async {
    phase('end');
    await stdout.flush();
    exit(0);
  }
}
