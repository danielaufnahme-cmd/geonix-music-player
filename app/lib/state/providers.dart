import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../api/client.dart';
import '../models/download.dart';
import '../models/lyrics.dart';
import '../models/library_group.dart';
import '../models/playlist.dart';
import '../models/track.dart';

final apiProvider = Provider<ApiClient>((ref) => ApiClient());

/// Used to show snackbars from anywhere (actions, controllers).
final messengerKeyProvider = Provider<GlobalKey<ScaffoldMessengerState>>((ref) => GlobalKey());

void showMessage(Ref ref, String text) {
  ref.read(messengerKeyProvider).currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Focus node of the search field, so Ctrl+F can jump into it.
final searchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'search');
  ref.onDispose(node.dispose);
  return node;
});

// ------------------------------------------------------------- navigation

sealed class AppRoute {
  const AppRoute();
}

class HomeRoute extends AppRoute {
  const HomeRoute();
}

class SearchRoute extends AppRoute {
  const SearchRoute();
}

class LibraryRoute extends AppRoute {
  const LibraryRoute([this.tab = 0]);
  final int tab;
}

class DownloadsRoute extends AppRoute {
  const DownloadsRoute();
}

class PlaylistRoute extends AppRoute {
  const PlaylistRoute(this.id);
  final int id;
}

class ArtistRoute extends AppRoute {
  const ArtistRoute(this.name);
  final String name;
}

class AlbumRoute extends AppRoute {
  const AlbumRoute(this.name, this.artist);
  final String name;
  final String artist;
}

/// Simple navigation stack: the sidebar resets it, pages push onto it.
class NavController extends Notifier<List<AppRoute>> {
  @override
  List<AppRoute> build() => const [HomeRoute()];

  AppRoute get current => state.last;
  bool get canPop => state.length > 1;

  void go(AppRoute root) => state = [root];
  void push(AppRoute route) => state = [...state, route];
  void pop() {
    if (canPop) state = state.sublist(0, state.length - 1);
  }
}

final navProvider = NotifierProvider<NavController, List<AppRoute>>(NavController.new);

// --------------------------------------------------------------- library

class LibrarySort extends Notifier<String> {
  @override
  String build() => 'added';
  void set(String value) => state = value;
}

final librarySortProvider = NotifierProvider<LibrarySort, String>(LibrarySort.new);

class LibraryFilter extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value;
}

final libraryFilterProvider = NotifierProvider<LibraryFilter, String>(LibraryFilter.new);

final libraryTracksProvider = FutureProvider<List<Track>>((ref) {
  return ref.watch(apiProvider).tracks(sort: ref.watch(librarySortProvider));
});

/// Library songs after the instant text filter.
final filteredLibraryProvider = Provider<AsyncValue<List<Track>>>((ref) {
  final q = ref.watch(libraryFilterProvider).trim().toLowerCase();
  return ref.watch(libraryTracksProvider).whenData((tracks) {
    if (q.isEmpty) return tracks;
    return [
      for (final t in tracks)
        if (t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q) || t.album.toLowerCase().contains(q))
          t,
    ];
  });
});

final recentlyPlayedProvider = FutureProvider<List<Track>>((ref) async {
  final tracks = await ref.watch(apiProvider).tracks(sort: 'recent');
  return tracks.where((t) => t.lastPlayed != null).take(16).toList();
});

final topTracksProvider = FutureProvider<List<Track>>((ref) async {
  final tracks = await ref.watch(apiProvider).tracks(sort: 'plays');
  return tracks.where((t) => t.playCount > 0).take(16).toList();
});

final artistsProvider = FutureProvider<List<Artist>>((ref) => ref.watch(apiProvider).artists());
final albumsProvider = FutureProvider<List<Album>>((ref) => ref.watch(apiProvider).albums());
final playlistsProvider = FutureProvider<List<Playlist>>((ref) => ref.watch(apiProvider).playlists());
final playlistProvider = FutureProvider.family<Playlist, int>((ref, id) => ref.watch(apiProvider).playlist(id));

/// Refresh everything that shows library contents.
/// Pass `ref.invalidate` from either a provider or a widget.
void refreshLibrary(void Function(ProviderOrFamily) invalidate) {
  for (final p in <ProviderOrFamily>[
    libraryTracksProvider,
    recentlyPlayedProvider,
    topTracksProvider,
    artistsProvider,
    albumsProvider,
    playlistsProvider,
    playlistProvider,
  ]) {
    invalidate(p);
  }
}

// ---------------------------------------------------------------- search

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value;
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(SearchQuery.new);

bool looksLikePlaylistUrl(String text) {
  final t = text.trim();
  return (t.startsWith('http://') || t.startsWith('https://')) && t.contains('list=');
}

final searchResultsProvider = FutureProvider<List<Track>>((ref) async {
  final q = ref.watch(searchQueryProvider).trim();
  if (q.isEmpty || looksLikePlaylistUrl(q)) return const [];
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  // Debounce: wait until typing pauses.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (cancelled) return const [];
  return ref.read(apiProvider).search(q);
});

final playlistPreviewProvider = FutureProvider.family<PlaylistPreview, String>(
  (ref, url) => ref.watch(apiProvider).playlistInfo(url),
);

// ------------------------------------------------------------- downloads

/// Download queue, kept live through the backend's SSE stream.
class DownloadsController extends Notifier<List<Download>> {
  StreamSubscription<DownloadEvent>? _sub;
  Timer? _reconnect;
  Timer? _refreshDebounce;
  bool _disposed = false;

  @override
  List<Download> build() {
    ref.onDispose(() {
      _disposed = true;
      _sub?.cancel();
      _reconnect?.cancel();
      _refreshDebounce?.cancel();
    });
    _load();
    _listen();
    return const [];
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(apiProvider).downloads();
      if (!_disposed) state = list;
    } catch (_) {
      // Backend not up yet; the stream reconnect will retry.
    }
  }

  void _listen() {
    _sub?.cancel();
    _sub = ref.read(apiProvider).downloadEvents().listen(
      (event) {
        if (event.resync) {
          _load();
        } else if (event.download != null) {
          _apply(event.download!);
        }
      },
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 2), () {
      _load();
      _listen();
    });
  }

  void _apply(Download d) {
    final i = state.indexWhere((x) => x.id == d.id);
    final previous = i >= 0 ? state[i] : null;
    var next = i >= 0 ? ([...state]..[i] = d) : [d, ...state];
    if (!d.isFailed) {
      // The backend drops older failures of a song once it's tried again.
      next = [for (final x in next) if (x.id == d.id || x.videoId != d.videoId || !x.isFailed) x];
    }
    state = next;
    final justFinished = d.status == 'done' && previous?.status != 'done';
    if (justFinished) {
      // A song joined the library: refresh views, batched for playlist imports.
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(const Duration(milliseconds: 600), () {
        refreshLibrary(ref.invalidate);
        ref.invalidate(searchResultsProvider);
        ref.invalidate(recommendationsProvider);
      });
    }
  }

  Future<void> download(Track track) async {
    try {
      final d = await ref.read(apiProvider).downloadTrack(track.videoId);
      _apply(d);
      if (d.status == 'skipped') showMessage(ref, '“${track.title}” is already in your library');
    } on Exception catch (e) {
      showMessage(ref, 'Download failed: $e');
    }
  }

  /// Remove finished download records from the list (never the files).
  Future<void> remove(Iterable<String> ids) async {
    final picked = ids.toSet();
    final removable = [for (final d in state) if (picked.contains(d.id) && !d.isActive) d.id];
    if (removable.isEmpty) return;
    try {
      if (removable.length == 1) {
        await ref.read(apiProvider).deleteDownload(removable.first);
      } else {
        await ref.read(apiProvider).clearDownloads(ids: removable);
      }
      final gone = removable.toSet();
      state = [for (final d in state) if (!gone.contains(d.id)) d];
    } on Exception catch (e) {
      showMessage(ref, 'Could not remove: $e');
      _load();
    }
  }

  /// Clear all finished ("done", includes skipped) or all failed records.
  Future<int> clear(String status) async {
    try {
      final n = await ref.read(apiProvider).clearDownloads(status: status);
      state = [
        for (final d in state)
          if (!(status == 'failed' ? d.isFailed : d.isFinished)) d
      ];
      return n;
    } on Exception catch (e) {
      showMessage(ref, 'Could not clear: $e');
      _load();
      return 0;
    }
  }

  Future<void> retryAllFailed() async {
    final failed = [for (final d in state) if (d.isFailed) d];
    for (final d in failed) {
      await retry(d);
    }
  }

  Future<void> retry(Download d) async {
    try {
      _apply(await ref.read(apiProvider).retryDownload(d.id));
    } on Exception catch (e) {
      showMessage(ref, 'Retry failed: $e');
    }
  }
}

final downloadsProvider = NotifierProvider<DownloadsController, List<Download>>(DownloadsController.new);

/// Latest download per song, for progress rings on song rows.
final downloadByVideoProvider = Provider<Map<String, Download>>((ref) {
  final map = <String, Download>{};
  for (final d in ref.watch(downloadsProvider).reversed) {
    map[d.videoId] = d;
  }
  return map;
});

final activeDownloadCountProvider = Provider<int>(
  (ref) => ref.watch(downloadsProvider).where((d) => d.isActive).length,
);

// ------------------------------------------------------- recommendations

class RecommendationsController extends AsyncNotifier<List<Track>> {
  @override
  Future<List<Track>> build() => ref.watch(apiProvider).recommendations();

  /// Rebuild the taste profile and the Discover Mix.
  Future<void> refresh() async {
    final previous = state;
    state = const AsyncLoading<List<Track>>();
    try {
      state = AsyncData(await ref.read(apiProvider).refreshRecommendations());
      ref.invalidate(playlistsProvider);
      ref.invalidate(playlistProvider);
    } on Exception catch (e) {
      state = previous;
      showMessage(ref, e.toString());
    }
  }
}

final recommendationsProvider =
    AsyncNotifierProvider<RecommendationsController, List<Track>>(RecommendationsController.new);

// ---------------------------------------------------------------- lyrics

/// Lyrics for a song (cached by the backend). Errors become "no lyrics".
final lyricsProvider = FutureProvider.family<Lyrics, String>((ref, videoId) async {
  try {
    return await ref.watch(apiProvider).lyrics(videoId);
  } on Exception {
    return Lyrics.none;
  }
});
