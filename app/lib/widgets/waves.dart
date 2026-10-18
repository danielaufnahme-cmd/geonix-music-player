import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Shared animation clock for every wave in the app. One [Ticker] (owned by
/// [WaveClockScope]) drives it; painters listen to it via `repaint:` so a
/// frame only repaints the wave layers, never rebuilds widgets.
///
/// [energy] eases towards 1 while music plays and towards 0 when paused, so
/// waves calm down smoothly instead of jumping. After [idleStop] paused the
/// ticker stops completely and the waves freeze (no CPU use when idle).
class WaveClock extends ChangeNotifier {
  WaveClock._();

  /// A clock that never moves; used when there is no [WaveClockScope].
  static final WaveClock still = WaveClock._();

  static const idleStop = Duration(seconds: 10);

  double _phase = 0;
  double _energy = 0;
  bool _ticking = false;
  int _frame = 0;

  /// Notifies on every other clock frame (~30 fps). Calm background layers
  /// repaint on this instead of the clock to halve their raster cost.
  final ChangeNotifier halfRate = _Pulse();

  /// Wave travel in "seconds"; advances faster while playing.
  double get phase => _phase;

  /// 0 = calm (paused / nothing playing), 1 = lively (playing).
  double get energy => _energy;

  /// Whether frames are currently being produced.
  bool get isTicking => _ticking;

  /// 0..1 slow pulse used for "breathing" glows; flat when calm.
  double get breath => 0.5 + 0.5 * math.sin(_phase * 1.7);

  void _advance(double dt, bool playing) {
    final target = playing ? 1.0 : 0.0;
    _energy += (target - _energy) * (1 - math.exp(-dt * 2.2));
    if ((_energy - target).abs() < 0.001) _energy = target;
    _phase += dt * (0.12 + 0.88 * _energy);
    notifyListeners();
    if ((_frame++).isEven) (halfRate as _Pulse).pulse();
  }

  @override
  void dispose() {
    halfRate.dispose();
    super.dispose();
  }
}

class _Pulse extends ChangeNotifier {
  void pulse() => notifyListeners();
}

/// Owns the single wave [Ticker]. Put it above the [Navigator] (e.g. in
/// `MaterialApp.builder`) so every screen and route shares one clock.
class WaveClockScope extends StatefulWidget {
  const WaveClockScope({super.key, required this.playing, required this.child});

  final bool playing;
  final Widget child;

  @override
  State<WaveClockScope> createState() => _WaveClockScopeState();
}

class _WaveClockScopeState extends State<WaveClockScope> with SingleTickerProviderStateMixin {
  final _clock = WaveClock._();
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  double _idle = 0;
  bool _started = false;

  @override
  void didUpdateWidget(covariant WaveClockScope old) {
    super.didUpdateWidget(old);
    if (widget.playing != old.playing) {
      _idle = 0;
      _start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animationsDisabled) {
      if (_ticker.isActive) _stop();
    } else if (!_started) {
      // First start happens here: MediaQuery can't be read in initState.
      _started = true;
      _start();
    }
  }

  bool get _animationsDisabled => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _start() {
    if (_ticker.isActive || _animationsDisabled) return;
    _last = Duration.zero;
    _clock._ticking = true;
    _ticker.start();
  }

  void _stop() {
    _ticker.stop();
    _clock._ticking = false;
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _clock._advance(dt, widget.playing);
    if (widget.playing) {
      _idle = 0;
    } else {
      _idle += dt;
      if (_idle * 1000 >= WaveClock.idleStop.inMilliseconds && _clock.energy == 0) _stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _WaveClockInherited(clock: _clock, child: widget.child);
}

class _WaveClockInherited extends InheritedWidget {
  const _WaveClockInherited({required this.clock, required super.child});
  final WaveClock clock;

  @override
  bool updateShouldNotify(_WaveClockInherited old) => old.clock != clock;
}

extension WaveClockContext on BuildContext {
  /// The shared wave clock, or a frozen one outside a [WaveClockScope].
  WaveClock get waveClock => dependOnInheritedWidgetOfExactType<_WaveClockInherited>()?.clock ?? WaveClock.still;
}

Color _shiftHue(Color c, double degrees, {double lightness = 0}) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withHue((hsl.hue + degrees) % 360).withLightness((hsl.lightness + lightness).clamp(0.0, 1.0)).toColor();
}

/// Colors for the wave look, derived from the cover palette.
@immutable
class WaveColors {
  const WaveColors({required this.base, required this.aurora, required this.layers});

  /// Background fill under the aurora.
  final Color base;

  /// Soft moving light blobs (with alpha).
  final List<Color> aurora;

  /// Wave layers from back to front (with alpha).
  final List<Color> layers;

  factory WaveColors.from({required Color accent, required Color deep, required Brightness brightness}) {
    if (brightness == Brightness.dark) {
      return WaveColors(
        base: Color.lerp(deep, Colors.black, 0.35)!,
        aurora: [
          accent.withValues(alpha: 0.55),
          _shiftHue(accent, 38, lightness: 0.05).withValues(alpha: 0.35),
          _shiftHue(deep, -20, lightness: 0.12).withValues(alpha: 0.7),
        ],
        layers: [
          _shiftHue(accent, -28).withValues(alpha: 0.20),
          accent.withValues(alpha: 0.24),
          _shiftHue(accent, 32, lightness: 0.08).withValues(alpha: 0.22),
          Color.lerp(accent, Colors.white, 0.3)!.withValues(alpha: 0.16),
        ],
      );
    }
    final soft = HSLColor.fromColor(accent).withLightness(0.62).toColor();
    return WaveColors(
      base: Color.lerp(const Color(0xFFF5F5F8), accent, 0.07)!,
      aurora: [
        soft.withValues(alpha: 0.30),
        _shiftHue(soft, 38).withValues(alpha: 0.22),
        _shiftHue(soft, -30).withValues(alpha: 0.18),
      ],
      layers: [
        _shiftHue(soft, -28).withValues(alpha: 0.14),
        soft.withValues(alpha: 0.17),
        _shiftHue(soft, 32).withValues(alpha: 0.15),
        Color.lerp(soft, Colors.white, 0.3)!.withValues(alpha: 0.14),
      ],
    );
  }
}

/// Layered flowing sine waves filling the bottom [heightFactor] of the box.
class WaveLayersPainter extends CustomPainter {
  WaveLayersPainter({
    required this.clock,
    required this.colors,
    this.intensity = 1,
    this.heightFactor = 0.4,
    this.glow = false,
    Listenable? repaint,
  }) : super(repaint: repaint ?? clock);

  final WaveClock clock;
  final List<Color> colors;

  /// 0..1: scales opacity and amplitude (backgrounds use a low value).
  final double intensity;
  final double heightFactor;

  /// Soft glowing crest line on each wave (Now Playing).
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || colors.isEmpty || intensity <= 0) return;
    final t = clock.phase;
    final e = clock.energy;
    final n = colors.length;
    final band = size.height * heightFactor;
    final step = math.max(4.0, size.width / 140);

    for (var i = 0; i < n; i++) {
      final depth = n == 1 ? 1.0 : i / (n - 1); // 0 = back (higher), 1 = front (lower)
      final base = size.height - band * (1 - depth * 0.55);
      final amp = band * (0.06 + 0.10 * e) * (1 - depth * 0.3) * (0.55 + 0.45 * intensity);
      final k = 2 * math.pi / size.width * (0.9 + i * 0.42);
      final speed = (0.55 + i * 0.22) * (i.isEven ? 1 : -1);
      final phi = i * 1.9;
      double yAt(double x) =>
          base +
          amp *
              (0.65 * math.sin(k * x + t * speed * 2 + phi) +
                  0.35 * math.sin(k * 2.3 * x - t * speed * 1.4 + phi * 2.1));

      final crest = Path()..moveTo(0, yAt(0));
      for (var x = step; x <= size.width + step; x += step) {
        crest.lineTo(x, yAt(x));
      }
      final fill = Path.from(crest)
        ..lineTo(size.width + step, size.height)
        ..lineTo(0, size.height)
        ..close();

      final c = colors[i];
      final a = (c.a * intensity).clamp(0.0, 1.0);
      canvas.drawPath(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, base - amp), Offset(0, size.height), [
            c.withValues(alpha: a),
            c.withValues(alpha: a * 0.12),
          ]),
      );
      if (glow) {
        // Soft halo + bright core reads like a blurred glow without the cost
        // of blurring an animated path every frame.
        final crestAlpha = (a * 2.2).clamp(0.0, 0.8);
        canvas
          ..drawPath(
            crest,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 9
              ..strokeCap = StrokeCap.round
              ..color = c.withValues(alpha: crestAlpha * 0.14),
          )
          ..drawPath(
            crest,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4.5
              ..strokeCap = StrokeCap.round
              ..color = c.withValues(alpha: crestAlpha * 0.28),
          )
          ..drawPath(
            crest,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..color = c.withValues(alpha: crestAlpha),
          );
      }
    }
  }

  @override
  bool shouldRepaint(WaveLayersPainter old) =>
      old.clock != clock ||
      !listEquals(old.colors, colors) ||
      old.intensity != intensity ||
      old.heightFactor != heightFactor ||
      old.glow != glow;
}

/// Slowly drifting soft light blobs over a base color (a mesh-like
/// gradient), with an optional vignette.
class AuroraPainter extends CustomPainter {
  AuroraPainter({
    required this.clock,
    required this.base,
    required this.colors,
    this.intensity = 1,
    this.vignette = 0,
    Listenable? repaint,
  }) : super(repaint: repaint ?? clock);

  final WaveClock clock;
  final Color? base;
  final List<Color> colors;
  final double intensity;
  final double vignette;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    if (base != null) canvas.drawRect(rect, Paint()..color = base!);
    final t = clock.phase;
    final n = colors.length;
    final r = math.max(size.width, size.height);
    for (var i = 0; i < n; i++) {
      final c = colors[i];
      final center = Offset(
        size.width * (0.18 + 0.64 * (i / math.max(1, n - 1))) + size.width * 0.10 * math.sin(t * 0.21 * (i + 1) + i),
        size.height * (0.18 + 0.22 * i) + size.height * 0.08 * math.cos(t * 0.17 * (i + 1) + i * 2),
      );
      final a = (c.a * intensity).clamp(0.0, 1.0);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(center, r * (0.62 - i * 0.1), [c.withValues(alpha: a), c.withValues(alpha: 0)]),
      );
    }
    if (vignette > 0) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(
            size.center(Offset.zero),
            r * 0.78,
            [Colors.transparent, Colors.black.withValues(alpha: vignette)],
            [0.55, 1],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(AuroraPainter old) =>
      old.clock != clock ||
      old.base != base ||
      !listEquals(old.colors, colors) ||
      old.intensity != intensity ||
      old.vignette != vignette;
}

/// The shared animated wave/aurora background. Every screen uses this with a
/// different [intensity]: calm behind lists, full on Now Playing. Colors fade
/// smoothly when the song (and so [accent]/[deep]) changes.
class WaveBackground extends StatelessWidget {
  const WaveBackground({
    super.key,
    required this.accent,
    required this.deep,
    this.intensity = 1,
    this.heightFactor = 0.4,
    this.aurora = true,
    this.paintBase = true,
    this.glow = false,
    this.vignette = 0,
    this.layers = 4,
    this.reducedRate = false,
    this.child,
  });

  final Color accent;
  final Color deep;
  final double intensity;
  final double heightFactor;
  final bool aurora;

  /// Fill the box with the base color first (off for overlays on glass).
  final bool paintBase;
  final bool glow;
  final double vignette;
  final int layers;

  /// Repaint at ~30 fps (calm backgrounds); the motion stays smooth because
  /// it is slow.
  final bool reducedRate;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final clock = context.waveClock;
    final repaint = reducedRate ? clock.halfRate : clock;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: accent),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, a, _) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: deep),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, d, _) {
          final colors = WaveColors.from(accent: a ?? accent, deep: d ?? deep, brightness: brightness);
          final paint = RepaintBoundary(
            child: CustomPaint(
              painter: aurora
                  ? AuroraPainter(
                      clock: clock,
                      base: paintBase ? colors.base : null,
                      colors: colors.aurora,
                      intensity: intensity,
                      vignette: vignette,
                      repaint: repaint,
                    )
                  : null,
              foregroundPainter: WaveLayersPainter(
                clock: clock,
                colors: colors.layers.take(layers).toList(),
                intensity: intensity,
                heightFactor: heightFactor,
                glow: glow,
                repaint: repaint,
              ),
              child: const SizedBox.expand(),
            ),
          );
          if (child == null) return paint;
          return Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(child: paint),
              child!,
            ],
          );
        },
      ),
    );
  }
}

/// A header backdrop: accent gradient whose bottom edge is a slow wave,
/// instead of a hard flat block.
class WaveHeaderBackground extends StatelessWidget {
  const WaveHeaderBackground({super.key, required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The animated edge gets its own layer so a frame never re-records the
    // header content (or the page around it).
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: color),
              duration: const Duration(milliseconds: 700),
              builder: (context, c, _) => CustomPaint(
                painter: _WaveEdgePainter(clock: context.waveClock, color: c ?? color),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _WaveEdgePainter extends CustomPainter {
  _WaveEdgePainter({required this.clock, required this.color}) : super(repaint: clock.halfRate);

  final WaveClock clock;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = clock.phase;
    final amp = 10 + 8 * clock.energy;
    final bottom = size.height - amp;
    final k = 2 * math.pi / size.width * 1.2;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0);
    for (var x = size.width; x >= -8; x -= 8) {
      path.lineTo(x, bottom + amp * 0.6 * math.sin(k * x + t * 0.9) + amp * 0.4 * math.sin(k * 2.1 * x - t * 0.6));
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [color, color.withValues(alpha: color.a * 0.35), color.withValues(alpha: 0)],
          [0, 0.7, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_WaveEdgePainter old) => old.clock != clock || old.color != color;
}

/// Soft colored glow behind [child] that gently breathes while playing.
class BreathingGlow extends StatelessWidget {
  const BreathingGlow({super.key, required this.color, required this.radius, required this.child});

  final Color color;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      // Own layer: the glow animates without repainting the cover or page.
      Positioned.fill(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _GlowPainter(clock: context.waveClock, color: color, radius: radius),
          ),
        ),
      ),
      RepaintBoundary(child: child),
    ],
  );
}

/// Blurred rounded-rect masks, rendered once per size. Blurring a large shape
/// every frame (with a changing sigma) was the most expensive part of Now
/// Playing; drawing a cached image scaled and tinted is nearly free.
class _GlowMaskCache {
  static const sigma = 50.0;
  static const _scale = 0.5; // half resolution: it's a blur anyway
  static final _images = <String, ui.Image>{};

  static ui.Image get(Size size, double radius) {
    final key = '${size.width.round()}x${size.height.round()}r${radius.round()}';
    final hit = _images[key];
    if (hit != null) return hit;
    if (_images.length >= 4) {
      final oldest = _images.keys.first;
      _images.remove(oldest)!.dispose();
    }
    const pad = sigma * 3;
    final w = ((size.width + pad * 2) * _scale).ceil();
    final h = ((size.height + pad * 2) * _scale).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_scale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, pad, size.width, size.height).inflate(10),
        Radius.circular(radius + 10),
      ),
      Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, sigma),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    return _images[key] = image;
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.clock, required this.color, required this.radius}) : super(repaint: clock);

  final WaveClock clock;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final b = clock.breath * clock.energy;
    final mask = _GlowMaskCache.get(size, radius);
    final scale = 1 + 0.07 * b;
    final dst = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: (size.width + _GlowMaskCache.sigma * 6) * scale,
      height: (size.height + _GlowMaskCache.sigma * 6) * scale,
    );
    canvas.drawImageRect(
      mask,
      Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble()),
      dst,
      Paint()
        ..filterQuality = FilterQuality.low
        ..colorFilter = ColorFilter.mode(color.withValues(alpha: 0.34 + 0.24 * b), BlendMode.srcIn),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.clock != clock || old.color != color || old.radius != radius;
}

/// Seek line: the played part is a travelling wave while music plays
/// (flattening smoothly when paused or while dragging), the rest is straight.
class WavySeekPainter extends CustomPainter {
  WavySeekPainter({
    required this.clock,
    required this.fraction,
    required this.active,
    required this.inactive,
    this.large = false,
    this.flat = false,
  }) : super(repaint: clock);

  final WaveClock clock;
  final double fraction;
  final Color active;
  final Color inactive;
  final bool large;
  final bool flat;

  static const double inset = 10;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= inset * 2) return;
    final y = size.height / 2;
    final left = inset;
    final right = size.width - inset;
    final x = left + (right - left) * fraction.clamp(0.0, 1.0);
    final stroke = large ? 4.0 : 3.0;
    final amp = flat ? 0.0 : (large ? 3.4 : 2.4) * clock.energy;
    final wavelength = large ? 30.0 : 22.0;
    final shift = clock.phase * 9;

    canvas.drawLine(
      Offset(x, y),
      Offset(right, y),
      Paint()
        ..color = inactive
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    if (x > left) {
      final path = Path()..moveTo(left, y);
      for (var px = left; px <= x; px += 1.5) {
        // Taper the wave near both ends so it meets the straight track cleanly.
        final taper = math.min(1.0, math.min(px - left, x - px) / 10);
        path.lineTo(px, y + amp * taper * math.sin((px - shift) / wavelength * 2 * math.pi));
      }
      path.lineTo(x, y);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = active
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    final thumbH = large ? 20.0 : 14.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, y), width: large ? 6 : 5, height: thumbH),
        const Radius.circular(3),
      ),
      Paint()..color = active,
    );
  }

  @override
  bool shouldRepaint(WavySeekPainter old) =>
      old.clock != clock ||
      old.fraction != fraction ||
      old.active != active ||
      old.inactive != inactive ||
      old.large != large ||
      old.flat != flat;
}
