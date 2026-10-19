import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../models/sync.dart';
import 'providers.dart';

/// What the devices icon and dialog show.
class SyncState {
  const SyncState({this.available, this.status, this.progress, this.running = false, this.loadError});

  /// null until the backend answered once; false when it has no sync routes
  /// (older backend), which hides the feature.
  final bool? available;
  final SyncStatus? status;

  /// Latest SSE `sync` event of the current run.
  final SyncEvent? progress;
  final bool running;

  /// Why the device list could not be loaded (backend offline etc.).
  final String? loadError;

  List<SyncDevice> get devices => status?.devices ?? const [];

  SyncState copyWith({
    bool? available,
    SyncStatus? status,
    SyncEvent? progress,
    bool clearProgress = false,
    bool? running,
    String? loadError,
    bool clearLoadError = false,
  }) =>
      SyncState(
        available: available ?? this.available,
        status: status ?? this.status,
        progress: clearProgress ? null : (progress ?? this.progress),
        running: running ?? this.running,
        loadError: clearLoadError ? null : (loadError ?? this.loadError),
      );
}

/// Device pairing and sync. Never polls on its own: the devices dialog
/// calls [load] every few seconds while it is open, and progress arrives
/// through the downloads SSE stream ([onEvent]).
class SyncController extends Notifier<SyncState> {
  bool _disposed = false;
  bool _silent = false;
  bool _starting = false;
  int _newSongs = 0;
  final List<String> _errors = [];
  Timer? _settle;
  Timer? _watchdog;
  Timer? _refresh;

  /// How long to wait for the next SSE event before asking the backend
  /// whether a sync is still running (in case an event was missed).
  static Duration watchdogDelay = const Duration(seconds: 45);

  /// Pause between startup attempts while the backend is still starting.
  static Duration startupRetryDelay = const Duration(seconds: 3);

  @override
  SyncState build() {
    ref.onDispose(() {
      _disposed = true;
      _settle?.cancel();
      _watchdog?.cancel();
      _refresh?.cancel();
    });
    return const SyncState();
  }

  ApiClient get _api => ref.read(apiProvider);

  static bool _missingRoute(Object e) =>
      (e is ApiException && (e.status == 404 || e.status == 405)) || e is FormatException || e is TypeError;

  /// Fetch this device's code and the paired devices. Returns false on failure.
  Future<bool> load() async {
    try {
      final status = await _api.syncDevices();
      if (_disposed) return false;
      final wasRunning = state.running;
      state = state.copyWith(
        available: true,
        status: status,
        running: status.syncing || (wasRunning && (_settle != null || _starting)),
        clearLoadError: true,
      );
      if (wasRunning && !status.syncing && _settle == null && !_starting) _finish();
      return true;
    } catch (e) {
      if (_disposed) return false;
      if (_missingRoute(e)) {
        state = state.copyWith(available: false);
      } else {
        state = state.copyWith(loadError: e.toString());
      }
      return false;
    }
  }

  /// Called once after the app starts: wait for the backend, then sync
  /// silently with paired devices if there are any.
  Future<void> startup({int attempts = 20}) async {
    for (var i = 0; i < attempts && !_disposed; i++) {
      if (await load()) break;
      if (state.available == false) return;
      await Future<void>.delayed(startupRetryDelay);
    }
    if (_disposed || state.available != true) return;
    if (state.status!.syncing) {
      _begin(silent: true);
    } else if (state.devices.isNotEmpty) {
      await run(silent: true);
    }
  }

  void _begin({required bool silent}) {
    _silent = silent;
    _newSongs = 0;
    _errors.clear();
    state = state.copyWith(running: true, progress: const SyncEvent(state: 'started'));
    _armWatchdog();
  }

  /// Start a sync with every online paired device (or just [deviceId]).
  /// [silent] runs only report new songs, never errors.
  Future<void> run({String? deviceId, bool silent = false}) async {
    if (state.running || state.available == false) return;
    _begin(silent: silent);
    _starting = true;
    try {
      await _api.runSync(deviceId: deviceId);
    } on ApiException catch (e) {
      if (e.status == 409) return; // Already syncing; events will follow.
      _watchdog?.cancel();
      if (_disposed) return;
      state = state.copyWith(running: false, clearProgress: true, available: _missingRoute(e) ? false : null);
      if (!silent && !_missingRoute(e)) showMessage(ref, 'Sync failed: $e');
    } finally {
      _starting = false;
    }
  }

  /// One `sync` event from the SSE stream.
  void onEvent(SyncEvent e) {
    if (_disposed) return;
    if (!state.running) {
      // Started elsewhere (the other device, or before we listened).
      _silent = true;
      _newSongs = 0;
      _errors.clear();
    }
    _settle?.cancel();
    _settle = null;
    state = state.copyWith(available: true, running: true, progress: e);
    _armWatchdog();
    if (!e.finished) return;
    if (e.isError) {
      _errors.add(e.device.isEmpty ? e.message : '${e.device}: ${e.message}');
    } else if (e.done > 0) {
      _newSongs += e.done;
      _refreshLibrary();
    }
    // More devices may follow; ask the backend whether the run is over.
    _settle = Timer(const Duration(milliseconds: 800), () async {
      if (await load() && !state.status!.syncing) {
        _settle = null;
        _finish();
      } else {
        _settle = null;
      }
    });
  }

  void _finish() {
    _watchdog?.cancel();
    if (_disposed) return;
    final last = state.progress;
    state = state.copyWith(running: false, progress: last);
    if (_newSongs > 0) {
      _refreshLibrary();
      showMessage(ref, 'Synced $_newSongs new ${_newSongs == 1 ? 'song' : 'songs'} from your devices');
    } else if (!_silent) {
      showMessage(ref, _errors.isNotEmpty ? 'Sync failed — ${_errors.join('; ')}' : 'Everything is already in sync');
    }
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(watchdogDelay, () async {
      if (!state.running || _disposed) return;
      if (await load() && !state.status!.syncing) {
        _finish();
      } else if (state.running) {
        _armWatchdog();
      }
    });
  }

  void _refreshLibrary() {
    _refresh?.cancel();
    _refresh = Timer(const Duration(milliseconds: 600), () {
      if (_disposed) return;
      refreshLibrary(ref.invalidate);
      ref.invalidate(recommendationsProvider);
    });
  }

  /// Pair with the device showing [code]. Returns an error message, or null on success.
  Future<String?> pair(String code) async {
    final clean = normalizePairCode(code);
    if (clean.length != 6) return 'Codes have 6 letters.';
    try {
      final device = await _api.pairDevice(clean);
      await load();
      if (!_disposed) {
        final s = state.status;
        if (s != null && !s.devices.any((d) => d.id == device.id)) {
          state = state.copyWith(status: s.copyWith(devices: [...s.devices, device]));
        }
      }
      return null;
    } on ApiException catch (e) {
      if (e.isOffline) return e.message;
      if (e.status == 429) return 'Too many tries. Wait a minute and try again.';
      if (e.status == 404 && e.message.toLowerCase() == 'not found') {
        return 'This backend does not support device sync yet.';
      }
      if (e.status == 404) return e.message;
      return 'Could not pair: ${e.message}';
    } catch (e) {
      return 'Could not pair: $e';
    }
  }

  Future<void> remove(String id) async {
    final s = state.status;
    if (s != null) {
      state = state.copyWith(status: s.copyWith(devices: [for (final d in s.devices) if (d.id != id) d]));
    }
    try {
      await _api.removeDevice(id);
    } on Exception catch (e) {
      showMessage(ref, 'Could not remove the device: $e');
      await load();
    }
  }

  Future<void> newCode() async {
    try {
      final me = await _api.newSyncCode();
      final s = state.status;
      if (s != null && !_disposed) state = state.copyWith(status: s.copyWith(thisDevice: me));
    } on Exception catch (e) {
      showMessage(ref, 'Could not make a new code: $e');
    }
  }
}

final syncProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);

/// Uppercase, letters only, at most 6 (I and O are never used in codes,
/// but people may type them; the backend just won't find a match).
String normalizePairCode(String input) {
  final letters = input.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
  return letters.length > 6 ? letters.substring(0, 6) : letters;
}

// ------------------------------------------------------ private listening

/// Private listening: plays are not used for recommendations.
/// null while unknown or when the backend lacks the setting (toggle hidden).
class PrivateListeningController extends Notifier<bool?> {
  bool _disposed = false;

  @override
  bool? build() {
    ref.onDispose(() => _disposed = true);
    return null;
  }

  /// Load from the backend; retries a few times while it is starting.
  Future<void> load({int attempts = 20}) async {
    for (var i = 0; i < attempts && !_disposed; i++) {
      try {
        final v = await ref.read(apiProvider).privateListening();
        if (!_disposed) state = v;
        return;
      } on ApiException catch (e) {
        if (!e.isOffline) return; // No such setting on this backend.
      } catch (_) {
        return;
      }
      await Future<void>.delayed(SyncController.startupRetryDelay);
    }
  }

  Future<void> toggle() async {
    final before = state;
    if (before == null) return;
    state = !before;
    try {
      final saved = await ref.read(apiProvider).setPrivateListening(!before);
      if (!_disposed) state = saved;
    } on Exception catch (e) {
      if (_disposed) return;
      state = before;
      showMessage(ref, 'Could not change private listening: $e');
    }
  }
}

final privateListeningProvider = NotifierProvider<PrivateListeningController, bool?>(PrivateListeningController.new);
