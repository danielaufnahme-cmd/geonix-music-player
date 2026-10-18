import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The desktop's color scheme, as written by the Caelestia shell to
/// `~/.local/state/caelestia/scheme.json` (Material You colors generated
/// from the wallpaper; hex values without '#').
@immutable
class DesktopScheme {
  const DesktopScheme({
    required this.brightness,
    required this.background,
    required this.surfaceLow,
    required this.surface,
    required this.surfaceHigh,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
  });

  final Brightness brightness;
  final Color background;
  final Color surfaceLow;
  final Color surface;
  final Color surfaceHigh;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;

  /// Parse scheme.json content. Returns null if it isn't a usable scheme.
  static DesktopScheme? tryParse(String source) {
    try {
      final json = jsonDecode(source);
      if (json is! Map<String, dynamic>) return null;
      final colours = json['colours'] ?? json['colors'];
      if (colours is! Map<String, dynamic>) return null;
      Color? c(List<String> keys) {
        for (final k in keys) {
          final v = colours[k];
          if (v is String) {
            final hex = v.replaceFirst('#', '').trim();
            if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return Color(0xFF000000 | int.parse(hex, radix: 16));
          }
        }
        return null;
      }

      final background = c(['background', 'surface']);
      final primary = c(['primary']);
      final onSurface = c(['onSurface', 'onBackground']);
      if (background == null || primary == null || onSurface == null) return null;
      final mode = json['mode'];
      final brightness = mode == 'light'
          ? Brightness.light
          : mode == 'dark'
              ? Brightness.dark
              : ThemeData.estimateBrightnessForColor(background);
      return DesktopScheme(
        brightness: brightness,
        background: background,
        surfaceLow: c(['surfaceContainerLow', 'surfaceContainerLowest']) ?? background,
        surface: c(['surfaceContainer', 'surface']) ?? background,
        surfaceHigh: c(['surfaceContainerHigh', 'surfaceContainerHighest', 'surfaceVariant']) ?? background,
        primary: primary,
        secondary: c(['secondary']) ?? primary,
        tertiary: c(['tertiary']) ?? primary,
        onSurface: onSurface,
        onSurfaceVariant: c(['onSurfaceVariant', 'outline']) ?? onSurface.withValues(alpha: 0.7),
        outline: c(['outlineVariant', 'outline']) ?? onSurface.withValues(alpha: 0.2),
      );
    } catch (_) {
      return null;
    }
  }

  /// Dark tone of the scheme for wave backgrounds when nothing plays.
  Color get deep => brightness == Brightness.dark
      ? Color.lerp(background, primary, 0.14)!
      : Color.lerp(background, primary, 0.10)!;

  @override
  bool operator ==(Object other) =>
      other is DesktopScheme &&
      other.brightness == brightness &&
      other.background == background &&
      other.surfaceLow == surfaceLow &&
      other.surface == surface &&
      other.surfaceHigh == surfaceHigh &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.tertiary == tertiary &&
      other.onSurface == onSurface &&
      other.onSurfaceVariant == onSurfaceVariant &&
      other.outline == outline;

  @override
  int get hashCode => Object.hash(brightness, background, surfaceLow, surface, surfaceHigh, primary, secondary,
      tertiary, onSurface, onSurfaceVariant, outline);
}

/// Pull a cover color's hue toward the desktop's primary hue (at most 25°),
/// like Material's "harmonize": the song still shows, but it fits the desktop.
Color harmonize(Color cover, Color primary, {double maxShift = 25}) {
  final c = HSLColor.fromColor(cover);
  final p = HSLColor.fromColor(primary);
  var diff = (p.hue - c.hue) % 360;
  if (diff > 180) diff -= 360;
  final shift = (diff * 0.5).clamp(-maxShift, maxShift);
  return c.withHue((c.hue + shift) % 360).toColor();
}

/// Where the app's base colors come from.
enum ThemeSource { desktop, geonix }

/// Path of the desktop scheme. GEONIX_SCHEME_FILE overrides it (tests, other shells).
String desktopSchemePath() {
  final override = Platform.environment['GEONIX_SCHEME_FILE'];
  if (override != null && override.isNotEmpty) return override;
  final home = Platform.environment['HOME'] ?? '';
  final state = Platform.environment['XDG_STATE_HOME'];
  final base = (state != null && state.isNotEmpty) ? state : '$home/.local/state';
  return '$base/caelestia/scheme.json';
}

/// The current desktop scheme, re-read whenever the file changes (e.g. a
/// new wallpaper). Null when the file is missing or invalid.
final desktopSchemeProvider = StreamProvider<DesktopScheme?>((ref) {
  final path = desktopSchemePath();
  final file = File(path);
  final controller = StreamController<DesktopScheme?>();
  DesktopScheme? last;
  var first = true;

  Future<void> load() async {
    DesktopScheme? scheme;
    try {
      if (await file.exists()) scheme = DesktopScheme.tryParse(await file.readAsString());
    } catch (_) {
      scheme = null;
    }
    // A half-written file parses as null; keep the last good scheme then.
    if (scheme == null && last != null && await file.exists()) return;
    if (first || scheme != last) {
      first = false;
      last = scheme;
      if (!controller.isClosed) controller.add(scheme);
    }
  }

  Timer? debounce;
  StreamSubscription<FileSystemEvent>? sub;
  // Watch the directory: the shell replaces the file instead of editing it.
  final dir = file.parent;
  if (dir.existsSync()) {
    sub = dir.watch().listen((event) {
      if (!event.path.endsWith('/${file.uri.pathSegments.last}')) return;
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 250), load);
    }, onError: (_) {});
  }
  load();
  ref.onDispose(() {
    debounce?.cancel();
    sub?.cancel();
    controller.close();
  });
  return controller.stream;
});

const _kSourceKey = 'theme_source';
const _kModeKey = 'theme_mode';

/// User's theme choice, saved between runs.
@immutable
class ThemeSettings {
  const ThemeSettings({this.source = ThemeSource.desktop, this.mode = ThemeMode.dark});
  final ThemeSource source;

  /// Light/dark for the Geonix palette (the desktop palette brings its own).
  final ThemeMode mode;

  ThemeSettings copyWith({ThemeSource? source, ThemeMode? mode}) =>
      ThemeSettings(source: source ?? this.source, mode: mode ?? this.mode);
}

class ThemeSettingsController extends Notifier<ThemeSettings> {
  @override
  ThemeSettings build() {
    _load();
    return const ThemeSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final source = prefs.getString(_kSourceKey) == 'geonix' ? ThemeSource.geonix : ThemeSource.desktop;
      final mode = prefs.getString(_kModeKey) == 'light' ? ThemeMode.light : ThemeMode.dark;
      state = ThemeSettings(source: source, mode: mode);
    } catch (_) {
      // No preferences store (e.g. tests): keep the defaults.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSourceKey, state.source.name);
      await prefs.setString(_kModeKey, state.mode == ThemeMode.light ? 'light' : 'dark');
    } catch (_) {}
  }

  void setSource(ThemeSource source) {
    state = state.copyWith(source: source);
    _save();
  }

  void toggleMode() {
    state = state.copyWith(mode: state.mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
    _save();
  }
}

final themeSettingsProvider = NotifierProvider<ThemeSettingsController, ThemeSettings>(ThemeSettingsController.new);

/// The desktop scheme when the user chose desktop colors and one exists.
final activeDesktopSchemeProvider = Provider<DesktopScheme?>((ref) {
  if (ref.watch(themeSettingsProvider.select((s) => s.source)) != ThemeSource.desktop) return null;
  return ref.watch(desktopSchemeProvider).asData?.value;
});

/// Effective light/dark mode: the desktop's when following it, else the user's.
final effectiveThemeModeProvider = Provider<ThemeMode>((ref) {
  final desktop = ref.watch(activeDesktopSchemeProvider);
  if (desktop != null) return desktop.brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
  return ref.watch(themeSettingsProvider.select((s) => s.mode));
});
