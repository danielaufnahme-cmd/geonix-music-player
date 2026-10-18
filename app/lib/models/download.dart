class Download {
  const Download({
    required this.id,
    required this.videoId,
    this.title = '',
    this.artist = '',
    this.status = 'queued',
    this.progress = 0,
    this.speed,
    this.error,
    this.playlistId,
    this.createdAt,
  });

  final String id;
  final String videoId;
  final String title;
  final String artist;

  /// "queued", "downloading", "done", "failed" or "skipped".
  final String status;

  /// 0–100.
  final double progress;
  final String? speed;
  final String? error;
  final int? playlistId;
  final DateTime? createdAt;

  bool get isActive => status == 'queued' || status == 'downloading';
  bool get isFailed => status == 'failed';
  bool get isFinished => status == 'done' || status == 'skipped';

  factory Download.fromJson(Map<String, dynamic> j) => Download(
        id: j['id'] as String,
        videoId: j['video_id'] as String,
        title: (j['title'] as String?) ?? '',
        artist: (j['artist'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'queued',
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        speed: j['speed'] as String?,
        error: j['error'] as String?,
        playlistId: (j['playlist_id'] as num?)?.toInt(),
        createdAt: j['created_at'] is num
            ? DateTime.fromMillisecondsSinceEpoch((j['created_at'] as num).toInt())
            : null,
      );
}
