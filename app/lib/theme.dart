import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'state/desktop_theme.dart';

/// Default accent before any song plays.
const Color kDefaultAccent = Color(0xFF8B7CFF);

/// Space at the bottom of scrolling content so it can scroll out from under
/// the floating glass player bar.
const double kPlayerBarHeight = 88;
const double kContentBottomPadding = kPlayerBarHeight + 32;

/// App-specific colors on top of Material's scheme. Lerps smoothly, so the
/// whole UI fades when the accent changes with the playing song.
@immutable
class GeonixPalette extends ThemeExtension<GeonixPalette> {
  const GeonixPalette({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.outline,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
  });

  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color outline;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;

  Color get accentSoft => accent.withValues(alpha: 0.16);

  static GeonixPalette forBrightness(Brightness b, Color accent) {
    final dark = b == Brightness.dark;
    final tuned = tuneAccent(accent, b);
    return GeonixPalette(
      background: dark ? const Color(0xFF0B0C10) : const Color(0xFFF5F5F8),
      surface: dark ? const Color(0xFF15161C) : const Color(0xFFFFFFFF),
      surfaceHigh: dark ? const Color(0xFF1F2029) : const Color(0xFFECECF2),
      outline: dark ? const Color(0x1FFFFFFF) : const Color(0x1A000000),
      text: dark ? const Color(0xFFF3F3F7) : const Color(0xFF121218),
      muted: dark ? const Color(0xFF9A9BA8) : const Color(0xFF686977),
      accent: tuned,
      onAccent: ThemeData.estimateBrightnessForColor(tuned) == Brightness.dark ? Colors.white : const Color(0xFF0B0C10),
    );
  }

  /// Base colors from the desktop scheme; the accent still follows the song.
  static GeonixPalette fromDesktop(DesktopScheme d, Color accent) {
    final tuned = tuneAccent(accent, d.brightness);
    return GeonixPalette(
      background: d.background,
      surface: d.surface,
      surfaceHigh: d.surfaceHigh,
      outline: d.outline.withValues(alpha: 0.45),
      text: d.onSurface,
      muted: d.onSurfaceVariant,
      accent: tuned,
      onAccent: ThemeData.estimateBrightnessForColor(tuned) == Brightness.dark ? Colors.white : const Color(0xFF0B0C10),
    );
  }

  static final GeonixPalette fallback = forBrightness(Brightness.dark, kDefaultAccent);

  @override
  GeonixPalette copyWith({Color? accent}) => GeonixPalette(
        background: background,
        surface: surface,
        surfaceHigh: surfaceHigh,
        outline: outline,
        text: text,
        muted: muted,
        accent: accent ?? this.accent,
        onAccent: onAccent,
      );

  @override
  GeonixPalette lerp(ThemeExtension<GeonixPalette>? other, double t) {
    if (other is! GeonixPalette) return this;
    return GeonixPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    );
  }
}

/// Keep cover-derived accents readable: bright enough on dark backgrounds,
/// deep enough on light ones, never grey.
Color tuneAccent(Color c, Brightness b) {
  final hsl = HSLColor.fromColor(c);
  final sat = hsl.saturation.clamp(0.45, 0.9);
  final light = b == Brightness.dark ? hsl.lightness.clamp(0.58, 0.72) : hsl.lightness.clamp(0.38, 0.5);
  return hsl.withSaturation(sat).withLightness(light).toColor();
}

extension GeonixTheme on BuildContext {
  GeonixPalette get gx => Theme.of(this).extension<GeonixPalette>() ?? GeonixPalette.fallback;
}

/// [desktop] supplies base colors when the user follows the desktop theme
/// (only used when its brightness matches [brightness]).
ThemeData buildTheme(Brightness brightness, Color accent, {DesktopScheme? desktop}) {
  final gx = desktop != null && desktop.brightness == brightness
      ? GeonixPalette.fromDesktop(desktop, accent)
      : GeonixPalette.forBrightness(brightness, accent);
  final scheme = ColorScheme.fromSeed(seedColor: gx.accent, brightness: brightness).copyWith(
    primary: gx.accent,
    onPrimary: gx.onAccent,
    surface: gx.surface,
    onSurface: gx.text,
    outlineVariant: gx.outline,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: gx.background,
    canvasColor: gx.background,
    splashFactory: InkSparkle.splashFactory,
  );
  final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(bodyColor: gx.text, displayColor: gx.text);
  return base.copyWith(
    textTheme: text,
    extensions: [gx],
    dividerTheme: DividerThemeData(color: gx.outline, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: gx.text),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: gx.surfaceHigh, borderRadius: BorderRadius.circular(8)),
      textStyle: text.bodySmall?.copyWith(color: gx.text),
      waitDuration: const Duration(milliseconds: 500),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: gx.surfaceHigh,
      contentTextStyle: text.bodyMedium?.copyWith(color: gx.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      width: 460,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: gx.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: gx.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: text.bodyMedium,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: gx.surfaceHigh,
      hintStyle: TextStyle(color: gx.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: gx.accent.withValues(alpha: 0.7), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: gx.accent,
      inactiveTrackColor: gx.text.withValues(alpha: 0.14),
      thumbColor: gx.text,
      overlayColor: gx.accent.withValues(alpha: 0.18),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 0, pressedElevation: 0),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      trackShape: const RoundedRectSliderTrackShape(),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: gx.accent,
      linearTrackColor: gx.text.withValues(alpha: 0.1),
      circularTrackColor: gx.text.withValues(alpha: 0.1),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(gx.text.withValues(alpha: 0.18)),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
  );
}
