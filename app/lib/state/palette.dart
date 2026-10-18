import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../theme.dart';
import 'providers.dart';

/// Colors taken from a cover image.
class CoverPalette {
  const CoverPalette({required this.accent, required this.deep});

  /// The most vivid prominent color.
  final Color accent;

  /// A dark version of the overall tone, for backgrounds and gradients.
  final Color deep;

  static const fallback = CoverPalette(accent: kDefaultAccent, deep: Color(0xFF1A1730));
}

/// Pick colors from raw RGBA pixels. Pixels are grouped into 18 hue
/// buckets weighted by how saturated and mid-bright they are; the heaviest
/// bucket wins. Greyscale covers keep the default accent.
CoverPalette paletteFromPixels(Uint8List rgba) {
  const buckets = 18;
  final weight = List<double>.filled(buckets, 0);
  final sumR = List<double>.filled(buckets, 0);
  final sumG = List<double>.filled(buckets, 0);
  final sumB = List<double>.filled(buckets, 0);
  double allR = 0, allG = 0, allB = 0;
  var count = 0;

  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    allR += r;
    allG += g;
    allB += b;
    count++;
    final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
    if (hsl.saturation < 0.22 || hsl.lightness < 0.12 || hsl.lightness > 0.9) continue;
    final w = hsl.saturation * (1 - (hsl.lightness - 0.5).abs() * 1.4);
    if (w <= 0) continue;
    final k = (hsl.hue / 360 * buckets).floor() % buckets;
    weight[k] += w;
    sumR[k] += r * w;
    sumG[k] += g * w;
    sumB[k] += b * w;
  }
  if (count == 0) return CoverPalette.fallback;

  final avg = Color.fromARGB(255, allR ~/ count, allG ~/ count, allB ~/ count);
  final avgHsl = HSLColor.fromColor(avg);
  final deep = avgHsl.withLightness(0.13).withSaturation((avgHsl.saturation * 0.8).clamp(0.0, 0.6)).toColor();

  var best = -1;
  for (var k = 0; k < buckets; k++) {
    if (best < 0 || weight[k] > weight[best]) best = k;
  }
  if (best < 0 || weight[best] < count * 0.02) {
    return CoverPalette(accent: kDefaultAccent, deep: deep);
  }
  final w = weight[best];
  final accent = Color.fromARGB(255, (sumR[best] / w).round(), (sumG[best] / w).round(), (sumB[best] / w).round());
  final deepFromAccent = HSLColor.fromColor(accent).withLightness(0.14).withSaturation(0.45).toColor();
  return CoverPalette(accent: accent, deep: Color.lerp(deep, deepFromAccent, 0.6)!);
}

Future<CoverPalette> paletteFromImageBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 40, targetHeight: 40);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  frame.image.dispose();
  codec.dispose();
  if (data == null) return CoverPalette.fallback;
  return paletteFromPixels(data.buffer.asUint8List());
}

final coverPaletteProvider = FutureProvider.family<CoverPalette, String>((ref, videoId) async {
  final api = ref.watch(apiProvider);
  try {
    final res = await http.get(Uri.parse(api.coverUrl(videoId)));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return CoverPalette.fallback;
    return await paletteFromImageBytes(res.bodyBytes);
  } catch (_) {
    return CoverPalette.fallback;
  }
});
