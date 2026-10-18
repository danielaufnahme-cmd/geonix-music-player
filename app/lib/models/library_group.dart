class Artist {
  const Artist({required this.name, required this.trackCount, required this.coverTrackId});
  final String name;
  final int trackCount;
  final String coverTrackId;

  factory Artist.fromJson(Map<String, dynamic> j) => Artist(
        name: (j['name'] as String?) ?? '',
        trackCount: (j['track_count'] as num?)?.toInt() ?? 0,
        coverTrackId: (j['cover_track_id'] as String?) ?? '',
      );
}

class Album {
  const Album({required this.name, required this.artist, required this.trackCount, required this.coverTrackId});
  final String name;
  final String artist;
  final int trackCount;
  final String coverTrackId;

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        name: (j['name'] as String?) ?? '',
        artist: (j['artist'] as String?) ?? '',
        trackCount: (j['track_count'] as num?)?.toInt() ?? 0,
        coverTrackId: (j['cover_track_id'] as String?) ?? '',
      );
}
