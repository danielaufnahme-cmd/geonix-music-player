/// A song. Library songs, search results and recommendations share this
/// shape; [downloaded] tells them apart.
class Track {
  const Track({
    required this.videoId,
    required this.title,
    this.artist = '',
    this.album = '',
    this.durationSec = 0,
    this.thumbnailUrl = '',
    this.filePath,
    this.downloaded = false,
    this.playCount = 0,
    this.lastPlayed,
    this.addedAt,
    this.becauseArtist,
    this.becauseVideoId,
  });

  final String videoId;
  final String title;
  final String artist;
  final String album;
  final int durationSec;
  final String thumbnailUrl;
  final String? filePath;
  final bool downloaded;
  final int playCount;
  final DateTime? lastPlayed;
  final DateTime? addedAt;

  /// Set on recommendations: the library artist this song was found through.
  final String? becauseArtist;
  final String? becauseVideoId;

  Duration get duration => Duration(seconds: durationSec);

  static DateTime? _date(Object? ms) =>
      ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        videoId: j['video_id'] as String,
        title: (j['title'] as String?) ?? 'Unknown title',
        artist: (j['artist'] as String?) ?? '',
        album: (j['album'] as String?) ?? '',
        durationSec: (j['duration_sec'] as num?)?.toInt() ?? 0,
        thumbnailUrl: (j['thumbnail_url'] as String?) ?? '',
        filePath: j['file_path'] as String?,
        downloaded: (j['downloaded'] as bool?) ?? false,
        playCount: (j['play_count'] as num?)?.toInt() ?? 0,
        lastPlayed: _date(j['last_played']),
        addedAt: _date(j['added_at']),
        becauseArtist: j['because_artist'] as String?,
        becauseVideoId: j['because_video_id'] as String?,
      );

  Track copyWith({bool? downloaded, int? playCount}) => Track(
        videoId: videoId,
        title: title,
        artist: artist,
        album: album,
        durationSec: durationSec,
        thumbnailUrl: thumbnailUrl,
        filePath: filePath,
        downloaded: downloaded ?? this.downloaded,
        playCount: playCount ?? this.playCount,
        lastPlayed: lastPlayed,
        addedAt: addedAt,
        becauseArtist: becauseArtist,
        becauseVideoId: becauseVideoId,
      );

  @override
  bool operator ==(Object other) => other is Track && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;
}
