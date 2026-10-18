import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/download.dart';
import '../models/lyrics.dart';
import '../models/library_group.dart';
import '../models/playlist.dart';
import '../models/track.dart';

/// Backend address. Override with `--dart-define=GEONIX_API=http://127.0.0.1:7979`.
const String kApiBase = String.fromEnvironment('GEONIX_API', defaultValue: 'http://127.0.0.1:7878');

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;

  bool get isOffline => status == 0;

  @override
  String toString() => message;
}

/// One message from `GET /api/downloads/events`.
class DownloadEvent {
  const DownloadEvent.update(Download this.download) : resync = false;
  const DownloadEvent.resync()
      : download = null,
        resync = true;
  final Download? download;
  final bool resync;
}

/// Talks to the Rust backend. The app never contacts anything else.
class ApiClient {
  ApiClient({this.baseUrl = kApiBase, http.Client? client}) : _http = client ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  String coverUrl(String videoId) => '$baseUrl/api/tracks/$videoId/cover';
  String streamUrl(String videoId) => '$baseUrl/api/tracks/$videoId/stream';

  Uri _uri(String path, [Map<String, String?>? query]) {
    final q = <String, String>{
      for (final e in (query ?? const <String, String?>{}).entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    return Uri.parse('$baseUrl$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String?>? query}) async {
    final req = http.Request(method, _uri(path, query));
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req)).timeout(const Duration(minutes: 3));
    } on TimeoutException {
      throw ApiException(0, 'The Geonix backend took too long to answer.');
    } on http.ClientException {
      throw ApiException(0, 'Can\'t reach the Geonix backend on $baseUrl. Is it running?');
    }
    final text = utf8.decode(res.bodyBytes);
    final decoded = text.isEmpty ? null : jsonDecode(text);
    if (res.statusCode >= 400) {
      final msg = decoded is Map && decoded['error'] is String ? decoded['error'] as String : 'Error ${res.statusCode}';
      throw ApiException(res.statusCode, msg);
    }
    return decoded;
  }

  List<Track> _tracks(dynamic json) => [for (final t in json as List) Track.fromJson(t as Map<String, dynamic>)];

  Future<bool> health() async {
    final j = await _send('GET', '/api/health') as Map<String, dynamic>;
    return j['status'] == 'ok';
  }

  Future<List<Track>> search(String query, {int limit = 25}) async =>
      _tracks(await _send('GET', '/api/search', query: {'q': query, 'limit': '$limit'}));

  Future<List<Track>> tracks({String? sort, String? q}) async =>
      _tracks(await _send('GET', '/api/tracks', query: {'sort': sort, 'q': q}));

  Future<Track> played(String videoId) async =>
      Track.fromJson(await _send('POST', '/api/tracks/$videoId/played') as Map<String, dynamic>);

  Future<void> deleteTrack(String videoId, {bool deleteFile = false}) =>
      _send('DELETE', '/api/tracks/$videoId', query: {'delete_file': deleteFile ? 'true' : null});

  Future<List<Artist>> artists() async =>
      [for (final a in await _send('GET', '/api/artists') as List) Artist.fromJson(a as Map<String, dynamic>)];

  Future<List<Album>> albums() async =>
      [for (final a in await _send('GET', '/api/albums') as List) Album.fromJson(a as Map<String, dynamic>)];

  Future<List<Playlist>> playlists() async =>
      [for (final p in await _send('GET', '/api/playlists') as List) Playlist.fromJson(p as Map<String, dynamic>)];

  Future<Playlist> playlist(int id) async =>
      Playlist.fromJson(await _send('GET', '/api/playlists/$id') as Map<String, dynamic>);

  Future<Playlist> createPlaylist(String name) async =>
      Playlist.fromJson(await _send('POST', '/api/playlists', body: {'name': name}) as Map<String, dynamic>);

  Future<Playlist> renamePlaylist(int id, String name) async =>
      Playlist.fromJson(await _send('PATCH', '/api/playlists/$id', body: {'name': name}) as Map<String, dynamic>);

  Future<void> deletePlaylist(int id) => _send('DELETE', '/api/playlists/$id');

  Future<Playlist> addToPlaylist(int id, String videoId) async => Playlist.fromJson(
      await _send('POST', '/api/playlists/$id/tracks', body: {'track_id': videoId}) as Map<String, dynamic>);

  Future<Playlist> removeFromPlaylist(int id, String videoId) async =>
      Playlist.fromJson(await _send('DELETE', '/api/playlists/$id/tracks/$videoId') as Map<String, dynamic>);

  Future<Playlist> reorderPlaylist(int id, List<String> videoIds) async => Playlist.fromJson(
      await _send('PUT', '/api/playlists/$id/order', body: {'track_ids': videoIds}) as Map<String, dynamic>);

  Future<List<Download>> downloads() async =>
      [for (final d in await _send('GET', '/api/downloads') as List) Download.fromJson(d as Map<String, dynamic>)];

  Future<Download> downloadTrack(String videoId) async =>
      Download.fromJson(await _send('POST', '/api/downloads', body: {'video_id': videoId}) as Map<String, dynamic>);

  /// Imports a whole playlist, optionally under a custom [name].
  /// Returns (local playlist id, songs queued, songs already in library).
  /// Import a YouTube playlist into a new playlist (optionally named [name]),
  /// or append it to the existing playlist [playlistId].
  Future<({int playlistId, String name, int queued, int skipped, int alreadyInPlaylist})> downloadPlaylist(
    String url, {
    String? name,
    int? playlistId,
  }) async {
    final body = {
      'playlist_url': url,
      'playlist_id': ?playlistId,
      if (playlistId == null && name != null && name.trim().isNotEmpty) 'name': name.trim(),
    };
    final j = await _send('POST', '/api/downloads', body: body) as Map<String, dynamic>;
    return (
      playlistId: (j['playlist_id'] as num).toInt(),
      name: (j['name'] as String?) ?? name ?? '',
      queued: (j['queued'] as num).toInt(),
      skipped: (j['skipped'] as num).toInt(),
      alreadyInPlaylist: (j['already_in_playlist'] as num?)?.toInt() ?? 0,
    );
  }

  /// Remove one finished download record (the music file stays).
  Future<void> deleteDownload(String id) => _send('DELETE', '/api/downloads/$id');

  /// Bulk-remove finished download records: by [status] ("done", "failed") or
  /// the given [ids]. Returns how many were removed.
  Future<int> clearDownloads({String? status, List<String>? ids}) async {
    final j = await _send('POST', '/api/downloads/clear', body: {
      'status': ?status,
      'ids': ?ids,
    }) as Map<String, dynamic>;
    return (j['removed'] as num?)?.toInt() ?? 0;
  }

  Future<Lyrics> lyrics(String videoId) async =>
      Lyrics.fromJson(await _send('GET', '/api/tracks/$videoId/lyrics') as Map<String, dynamic>);

  Future<Download> retryDownload(String id) async =>
      Download.fromJson(await _send('POST', '/api/downloads/$id/retry') as Map<String, dynamic>);

  Future<PlaylistPreview> playlistInfo(String url) async =>
      PlaylistPreview.fromJson(await _send('GET', '/api/playlist-info', query: {'url': url}) as Map<String, dynamic>);

  Future<List<Track>> recommendations({int limit = 40}) async =>
      _tracks(await _send('GET', '/api/recommendations', query: {'limit': '$limit'}));

  Future<List<Track>> refreshRecommendations() async =>
      _tracks(await _send('POST', '/api/recommendations/refresh'));

  /// Server-Sent Events stream of download changes. Ends when the
  /// connection drops; callers reconnect.
  Stream<DownloadEvent> downloadEvents() async* {
    final req = http.Request('GET', _uri('/api/downloads/events'))..headers['accept'] = 'text/event-stream';
    final client = http.Client();
    try {
      final res = await client.send(req);
      if (res.statusCode != 200) throw ApiException(res.statusCode, 'event stream failed');
      String? event;
      final data = StringBuffer();
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty) {
          if (event == 'download' && data.isNotEmpty) {
            yield DownloadEvent.update(Download.fromJson(jsonDecode(data.toString()) as Map<String, dynamic>));
          } else if (event == 'resync') {
            yield const DownloadEvent.resync();
          }
          event = null;
          data.clear();
        } else if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          data.write(line.substring(5).trimLeft());
        }
      }
    } finally {
      client.close();
    }
  }
}
