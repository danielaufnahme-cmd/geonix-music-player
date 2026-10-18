import 'track.dart';

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.kind = 'user',
    this.sourceUrl,
    this.trackCount = 0,
    this.durationSec = 0,
    this.coverTrackIds = const [],
    this.tracks = const [],
  });

  final int id;
  final String name;

  /// "user", "imported" (from YouTube) or "discover" (auto-generated mix).
  final String kind;
  final String? sourceUrl;
  final int trackCount;
  final int durationSec;

  /// First four songs, for the 2×2 cover mosaic.
  final List<String> coverTrackIds;

  /// Only filled when the full playlist was loaded.
  final List<Track> tracks;

  bool get isDiscover => kind == 'discover';

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: (j['id'] as num).toInt(),
        name: (j['name'] as String?) ?? 'Playlist',
        kind: (j['kind'] as String?) ?? 'user',
        sourceUrl: j['source_url'] as String?,
        trackCount: (j['track_count'] as num?)?.toInt() ?? 0,
        durationSec: (j['duration_sec'] as num?)?.toInt() ?? 0,
        coverTrackIds: [for (final id in (j['cover_track_ids'] as List?) ?? const []) id as String],
        tracks: [
          for (final t in (j['tracks'] as List?) ?? const []) Track.fromJson(t as Map<String, dynamic>)
        ],
      );
}

/// Preview of a YouTube playlist before importing it.
class PlaylistPreview {
  const PlaylistPreview({required this.title, required this.tracks});
  final String title;
  final List<Track> tracks;

  factory PlaylistPreview.fromJson(Map<String, dynamic> j) => PlaylistPreview(
        title: (j['title'] as String?) ?? 'Playlist',
        tracks: [for (final t in (j['tracks'] as List?) ?? const []) Track.fromJson(t as Map<String, dynamic>)],
      );
}
