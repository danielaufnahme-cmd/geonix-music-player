/// Song lyrics from `GET /api/tracks/{id}/lyrics`.
class LyricLine {
  const LyricLine(this.timeMs, this.text);

  /// Start time in the song; null for plain (unsynced) lyrics.
  final int? timeMs;
  final String text;
}

class Lyrics {
  const Lyrics({required this.synced, required this.lines, this.source});

  final bool synced;
  final List<LyricLine> lines;
  final String? source;

  static const none = Lyrics(synced: false, lines: []);

  bool get isEmpty => lines.isEmpty;

  factory Lyrics.fromJson(Map<String, dynamic> j) {
    final raw = j['lines'];
    final lines = <LyricLine>[
      if (raw is List)
        for (final l in raw)
          if (l is Map)
            LyricLine((l['time_ms'] as num?)?.toInt(), (l['text'] as String?)?.trim() ?? ''),
    ];
    final synced = j['synced'] == true && lines.every((l) => l.timeMs != null);
    return Lyrics(synced: synced, lines: lines, source: j['source'] as String?);
  }

  /// Index of the line being sung at [position] (the last line that has
  /// started), or -1 before the first line. Lines are sorted by time.
  int lineAt(Duration position, {Duration lead = const Duration(milliseconds: 250)}) {
    if (!synced || lines.isEmpty) return -1;
    final ms = position.inMilliseconds + lead.inMilliseconds;
    var lo = 0, hi = lines.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].timeMs! <= ms) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }
}
