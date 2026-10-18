import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../models/track.dart';
import '../theme.dart';
import 'desktop_theme.dart';
import 'palette.dart';
import 'providers.dart';

enum LoopMode { off, all, one }

@immutable
class PlayerState {
  const PlayerState({
    this.queue = const [],
    this.index = -1,
    this.originalQueue = const [],
    this.shuffle = false,
    this.repeat = LoopMode.off,
    this.playing = false,
    this.volume = 80,
  });

  final List<Track> queue;
  final int index;

  /// Queue order before shuffling, restored when shuffle is turned off.
  final List<Track> originalQueue;
  final bool shuffle;
  final LoopMode repeat;
  final bool playing;

  /// 0–100.
  final double volume;

  Track? get current => index >= 0 && index < queue.length ? queue[index] : null;
  List<Track> get upNext => index + 1 < queue.length ? queue.sublist(index + 1) : const [];
  bool get hasNext => index + 1 < queue.length || (repeat == LoopMode.all && queue.isNotEmpty);

  PlayerState copyWith({
    List<Track>? queue,
    int? index,
    List<Track>? originalQueue,
    bool? shuffle,
    LoopMode? repeat,
    bool? playing,
    double? volume,
  }) =>
      PlayerState(
        queue: queue ?? this.queue,
        index: index ?? this.index,
        originalQueue: originalQueue ?? this.originalQueue,
        shuffle: shuffle ?? this.shuffle,
        repeat: repeat ?? this.repeat,
        playing: playing ?? this.playing,
        volume: volume ?? this.volume,
      );
}

/// The media_kit player. Kept separate so widget tests never create one.
final mediaPlayerProvider = Provider<Player>((ref) {
  final player = Player(configuration: const PlayerConfiguration(title: 'Geonix Music Player'));
  ref.onDispose(player.dispose);
  return player;
});

/// Owns the queue (so it can be shuffled, reordered and edited) and drives
/// media_kit one song at a time.
class PlayerController extends Notifier<PlayerState> {
  final _subs = <StreamSubscription<dynamic>>[];
  final _random = Random();

  Player get _player => ref.read(mediaPlayerProvider);

  @override
  PlayerState build() {
    final player = ref.watch(mediaPlayerProvider);
    _subs
      ..add(player.stream.playing.listen((p) => state = state.copyWith(playing: p)))
      ..add(player.stream.completed.listen((done) {
        if (done) _onCompleted();
      }))
      ..add(player.stream.error.listen((e) {
        if (e.isNotEmpty) showMessage(ref, 'Playback problem: $e');
      }));
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
    });
    player.setVolume(80);
    return const PlayerState();
  }

  Future<void> _openCurrent() async {
    final track = state.current;
    if (track == null) return;
    await _player.open(Media(ref.read(apiProvider).streamUrl(track.videoId)), play: true);
    unawaited(_countPlay(track));
  }

  Future<void> _countPlay(Track track) async {
    try {
      await ref.read(apiProvider).played(track.videoId);
      ref.invalidate(recentlyPlayedProvider);
      ref.invalidate(topTracksProvider);
    } catch (_) {
      // Play counts are best effort.
    }
  }

  /// Play [tracks] starting at [start]. With [shuffle], the rest is shuffled.
  Future<void> playList(List<Track> tracks, {int start = 0, bool? shuffle}) async {
    if (tracks.isEmpty) return;
    final wantShuffle = shuffle ?? state.shuffle;
    final first = tracks[start.clamp(0, tracks.length - 1)];
    var queue = List<Track>.of(tracks);
    var index = queue.indexOf(first);
    if (wantShuffle) {
      final rest = List<Track>.of(tracks)..removeAt(index);
      rest.shuffle(_random);
      queue = [first, ...rest];
      index = 0;
    }
    state = state.copyWith(queue: queue, index: index, originalQueue: tracks, shuffle: wantShuffle);
    await _openCurrent();
  }

  Future<void> playTrack(Track track) => playList([track]);

  Future<void> playPause() async {
    if (state.current == null) return;
    await _player.playOrPause();
  }

  Future<void> next({bool auto = false}) async {
    if (state.queue.isEmpty) return;
    if (state.index + 1 < state.queue.length) {
      state = state.copyWith(index: state.index + 1);
    } else if (state.repeat == LoopMode.all) {
      state = state.copyWith(index: 0);
    } else {
      if (auto) {
        await _player.pause();
        await _player.seek(Duration.zero);
      }
      return;
    }
    await _openCurrent();
  }

  Future<void> previous() async {
    if (state.queue.isEmpty) return;
    // Like every player: restart the song unless we're at its very start.
    if (_player.state.position > const Duration(seconds: 3) || state.index == 0) {
      await _player.seek(Duration.zero);
      return;
    }
    state = state.copyWith(index: state.index - 1);
    await _openCurrent();
  }

  void _onCompleted() {
    if (state.repeat == LoopMode.one) {
      _player.seek(Duration.zero).then((_) => _player.play());
    } else {
      next(auto: true);
    }
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setVolume(double v) async {
    state = state.copyWith(volume: v.clamp(0, 100));
    await _player.setVolume(state.volume);
  }

  void toggleShuffle() {
    final current = state.current;
    if (!state.shuffle) {
      final upcoming = List<Track>.of(state.upNext)..shuffle(_random);
      final played = state.index >= 0 ? state.queue.sublist(0, state.index + 1) : <Track>[];
      state = state.copyWith(
        shuffle: true,
        originalQueue: state.queue,
        queue: [...played, ...upcoming],
      );
    } else {
      final original = state.originalQueue.isEmpty ? state.queue : state.originalQueue;
      final idx = current == null ? -1 : original.indexOf(current);
      state = state.copyWith(shuffle: false, queue: original, index: idx < 0 ? state.index : idx);
    }
  }

  void cycleRepeat() {
    state = state.copyWith(repeat: LoopMode.values[(state.repeat.index + 1) % LoopMode.values.length]);
  }

  /// Insert right after the current song.
  void playNext(Track track) {
    if (state.current == null) {
      playTrack(track);
      return;
    }
    final queue = List<Track>.of(state.queue)..insert(state.index + 1, track);
    state = state.copyWith(queue: queue, originalQueue: [...state.originalQueue, track]);
    showMessage(ref, '“${track.title}” plays next');
  }

  void addToQueue(Track track) {
    if (state.current == null) {
      playTrack(track);
      return;
    }
    state = state.copyWith(queue: [...state.queue, track], originalQueue: [...state.originalQueue, track]);
    showMessage(ref, 'Added “${track.title}” to the queue');
  }

  /// Reorder within "Up next" (indices relative to the upcoming list;
  /// [newIndex] is the final position, as given by `onReorderItem`).
  void reorderUpNext(int oldIndex, int newIndex) {
    final base = state.index + 1;
    final queue = List<Track>.of(state.queue);
    final item = queue.removeAt(base + oldIndex);
    queue.insert(base + newIndex, item);
    state = state.copyWith(queue: queue);
  }

  void removeFromUpNext(int upNextIndex) {
    final queue = List<Track>.of(state.queue)..removeAt(state.index + 1 + upNextIndex);
    state = state.copyWith(queue: queue);
  }

  void clearUpNext() {
    if (state.index < 0) return;
    state = state.copyWith(queue: state.queue.sublist(0, state.index + 1));
  }

  /// Jump to a song in "Up next".
  Future<void> jumpTo(int upNextIndex) async {
    state = state.copyWith(index: state.index + 1 + upNextIndex);
    await _openCurrent();
  }
}

final playerProvider = NotifierProvider<PlayerController, PlayerState>(PlayerController.new);

final currentTrackProvider = Provider<Track?>((ref) => ref.watch(playerProvider.select((s) => s.current)));

final positionProvider = StreamProvider<Duration>((ref) => ref.watch(mediaPlayerProvider).stream.position);
final durationProvider = StreamProvider<Duration>((ref) => ref.watch(mediaPlayerProvider).stream.duration);
final bufferingProvider = StreamProvider<bool>((ref) => ref.watch(mediaPlayerProvider).stream.buffering);

/// Colors of the playing song's cover (default palette when nothing plays).
final coverPaletteOfCurrentProvider = Provider<CoverPalette>((ref) {
  final track = ref.watch(currentTrackProvider);
  if (track == null) return CoverPalette.fallback;
  return ref.watch(coverPaletteProvider(track.videoId)).asData?.value ?? CoverPalette.fallback;
});

/// The palette the UI uses: the cover's colors, blended into the desktop
/// scheme when following the desktop (its primary color when nothing plays).
final currentPaletteProvider = Provider<CoverPalette>((ref) {
  final cover = ref.watch(coverPaletteOfCurrentProvider);
  final desktop = ref.watch(activeDesktopSchemeProvider);
  if (desktop == null) return cover;
  return desktopPalette(cover, desktop);
});

/// Cover colors adapted to the desktop scheme (pure, for tests).
CoverPalette desktopPalette(CoverPalette cover, DesktopScheme desktop) {
  if (cover == CoverPalette.fallback) return CoverPalette(accent: desktop.primary, deep: desktop.deep);
  return CoverPalette(
    accent: harmonize(cover.accent, desktop.primary),
    deep: Color.lerp(cover.deep, desktop.deep, 0.45)!,
  );
}

final accentProvider = Provider<Color>((ref) {
  final palette = ref.watch(currentPaletteProvider);
  return palette == CoverPalette.fallback ? kDefaultAccent : palette.accent;
});
