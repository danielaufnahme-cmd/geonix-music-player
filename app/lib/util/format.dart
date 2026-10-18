/// "3:05", or "1:02:03" for long durations.
String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// "1 hr 12 min" / "38 min" — for playlist totals.
String formatTotal(int seconds) {
  final d = Duration(seconds: seconds);
  if (d.inHours > 0) return '${d.inHours} hr ${d.inMinutes.remainder(60)} min';
  if (d.inMinutes > 0) return '${d.inMinutes} min';
  return '${d.inSeconds} sec';
}

String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

String greeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 5) return 'Good night';
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}
