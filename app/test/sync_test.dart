import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geonix_music_player/api/client.dart';
import 'package:geonix_music_player/models/sync.dart';
import 'package:geonix_music_player/state/providers.dart';
import 'package:geonix_music_player/state/sync.dart';
import 'package:geonix_music_player/util/format.dart';
import 'package:geonix_music_player/widgets/devices_dialog.dart';
import 'package:geonix_music_player/widgets/sidebar.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _status = {
  'this_device': {'id': 'me', 'name': 'desk', 'code': 'KQWXZP'},
  'devices': [
    {
      'id': 'lap',
      'name': 'laptop',
      'address': '100.64.0.2:7803',
      'online': true,
      'last_sync_at': '2026-10-19T10:00:00Z',
      'last_error': null,
    },
  ],
  'syncing': false,
};

/// In-memory backend for controller and widget tests.
class FakeApi extends ApiClient {
  FakeApi({this.supported = true, List<SyncDevice>? devices})
      : devices = devices ?? [SyncDevice.fromJson((_status['devices'] as List).first as Map<String, dynamic>)];

  bool supported;
  bool syncing = false;
  bool private = false;
  List<SyncDevice> devices;
  String code = 'KQWXZP';
  final calls = <String>[];

  void _check() {
    if (!supported) throw ApiException(404, 'not found');
  }

  @override
  Future<SyncStatus> syncDevices() async {
    calls.add('devices');
    _check();
    return SyncStatus(thisDevice: ThisDevice(id: 'me', name: 'desk', code: code), devices: devices, syncing: syncing);
  }

  @override
  Future<ThisDevice> newSyncCode() async {
    calls.add('code');
    code = 'ABCDEF';
    return ThisDevice(id: 'me', name: 'desk', code: code);
  }

  @override
  Future<SyncDevice> pairDevice(String code, {String? address}) async {
    calls.add('pair $code');
    _check();
    if (code != 'GHJKLM') throw ApiException(404, 'No device with that code found on your Tailscale network');
    final d = SyncDevice(id: 'new', name: 'phone-pc', online: true);
    devices = [...devices, d];
    return d;
  }

  @override
  Future<void> removeDevice(String id) async {
    calls.add('remove $id');
    devices = [for (final d in devices) if (d.id != id) d];
  }

  @override
  Future<void> runSync({String? deviceId}) async {
    calls.add('run');
    _check();
    syncing = true;
  }

  @override
  Future<bool> privateListening() async {
    _check();
    return private;
  }

  @override
  Future<bool> setPrivateListening(bool enabled) async {
    calls.add('private $enabled');
    return private = enabled;
  }
}

ProviderContainer _container(FakeApi api) {
  final c = ProviderContainer(overrides: [apiProvider.overrideWithValue(api)]);
  addTearDown(c.dispose);
  return c;
}

Widget _host(FakeApi api, Widget child) => ProviderScope(
      overrides: [apiProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  group('sync models and api', () {
    test('parses /api/sync/devices', () {
      final s = SyncStatus.fromJson(jsonDecode(jsonEncode(_status)) as Map<String, dynamic>);
      expect(s.thisDevice.code, 'KQWXZP');
      expect(s.devices.single.name, 'laptop');
      expect(s.devices.single.online, isTrue);
      expect(s.devices.single.lastSyncAt!.toUtc(), DateTime.utc(2026, 10, 19, 10));
      expect(s.devices.single.lastError, isNull);
      expect(s.syncing, isFalse);
    });

    test('sync event fraction and pair code cleanup', () {
      expect(SyncEvent.fromJson({'state': 'progress', 'done': 3, 'total': 4}).fraction, 0.75);
      expect(const SyncEvent(state: 'started').fraction, isNull);
      expect(normalizePairCode(' ab-cd ef9g '), 'ABCDEF');
      expect(formatAgo(DateTime(2026, 1, 1, 12), DateTime(2026, 1, 1, 12, 5)), '5 min ago');
      expect(formatAgo(DateTime(2026, 1, 1), DateTime(2026, 1, 3)), '2 days ago');
    });

    test('client sends the spec requests', () async {
      final seen = <String>[];
      final api = ApiClient(
        baseUrl: 'http://x',
        client: MockClient((req) async {
          seen.add('${req.method} ${req.url.path} ${req.body}');
          return switch (req.url.path) {
            '/api/sync/devices' => http.Response(jsonEncode(_status), 200),
            '/api/sync/pair' => http.Response(jsonEncode({'id': 'lap', 'name': 'laptop'}), 200),
            '/api/sync/run' => http.Response('', 202),
            '/api/settings/private-listening' => http.Response(jsonEncode({'enabled': true}), 200),
            '/api/tracks/abc/played' => http.Response('', 204),
            _ => http.Response('{"error":"not found"}', 404),
          };
        }),
      );
      expect((await api.syncDevices()).devices, hasLength(1));
      expect((await api.pairDevice('ABCDEF')).name, 'laptop');
      await api.runSync();
      await api.runSync(deviceId: 'lap');
      expect(await api.setPrivateListening(true), isTrue);
      expect(await api.played('abc'), isNull, reason: 'private listening answers 204');
      await expectLater(api.newSyncCode(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)));
      expect(seen, containsAllInOrder([
        'POST /api/sync/pair {"code":"ABCDEF"}',
        'POST /api/sync/run {}',
        'POST /api/sync/run {"device_id":"lap"}',
        'PUT /api/settings/private-listening {"enabled":true}',
      ]));
    });

    test('sync and settings changes always send a JSON content type', () async {
      // The backend refuses these without it (CSRF protection), even bodyless.
      final types = <String, String?>{};
      final api = ApiClient(
        baseUrl: 'http://x',
        client: MockClient((req) async {
          types['${req.method} ${req.url.path}'] = req.headers['content-type'];
          return switch (req.url.path) {
            '/api/sync/code' => http.Response(jsonEncode(_status['this_device']), 200),
            '/api/sync/pair' => http.Response(jsonEncode({'id': 'lap', 'name': 'laptop'}), 200),
            '/api/settings/private-listening' => http.Response(jsonEncode({'enabled': false}), 200),
            _ => http.Response(jsonEncode({'started': true}), 200),
          };
        }),
      );
      await api.newSyncCode();
      await api.pairDevice('ABCDEF');
      await api.removeDevice('lap');
      await api.runSync();
      await api.setPrivateListening(false);
      expect(types.keys, hasLength(5));
      for (final e in types.entries) {
        expect(e.value, startsWith('application/json'), reason: e.key);
      }
    });

    test('SSE stream yields sync events', () async {
      final mock = MockClient.streaming((req, _) async {
        const body = 'event: sync\n'
            'data: {"state":"progress","device":"laptop","done":2,"total":5,"message":""}\n\n'
            'event: download\ndata: {"id":"1","video_id":"v","status":"done"}\n\n';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      });
      final events = await http.runWithClient(
        () => ApiClient(baseUrl: 'http://x').downloadEvents().toList(),
        () => mock,
      );
      expect(events, hasLength(2));
      expect(events.first.sync!.device, 'laptop');
      expect(events.first.sync!.total, 5);
      expect(events.last.download!.videoId, 'v');
    });
  });

  group('SyncController', () {
    setUp(() {
      SyncController.startupRetryDelay = Duration.zero;
    });

    test('startup syncs silently when devices exist', () async {
      final api = FakeApi();
      final c = _container(api);
      await c.read(syncProvider.notifier).startup();
      expect(api.calls, ['devices', 'run']);
      expect(c.read(syncProvider).running, isTrue);
    });

    test('startup does nothing without devices', () async {
      final api = FakeApi(devices: []);
      final c = _container(api);
      await c.read(syncProvider.notifier).startup();
      expect(api.calls, ['devices']);
      expect(c.read(syncProvider).running, isFalse);
    });

    test('backend without sync routes hides the feature quietly', () async {
      final api = FakeApi(supported: false);
      final c = _container(api);
      await c.read(syncProvider.notifier).startup();
      expect(c.read(syncProvider).available, isFalse);
      await c.read(syncProvider.notifier).run();
      expect(api.calls, ['devices'], reason: 'no run attempted once unavailable');
    });

    test('done event ends the run once the backend is idle', () async {
      final api = FakeApi();
      final c = _container(api);
      final ctrl = c.read(syncProvider.notifier);
      await ctrl.load();
      await ctrl.run();
      ctrl.onEvent(const SyncEvent(state: 'progress', device: 'laptop', done: 1, total: 2));
      expect(c.read(syncProvider).progress!.done, 1);
      api.syncing = false;
      ctrl.onEvent(const SyncEvent(state: 'done', device: 'laptop', done: 2, total: 2));
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(c.read(syncProvider).running, isFalse);
      expect(c.read(syncProvider).progress!.state, 'done');
    });

    test('pair errors are friendly', () async {
      final api = FakeApi();
      final c = _container(api);
      final ctrl = c.read(syncProvider.notifier);
      await ctrl.load();
      expect(await ctrl.pair('abc'), 'Codes have 6 letters.');
      expect(await ctrl.pair('zzzzzz'), contains('No device with that code'));
      expect(await ctrl.pair('ghjklm'), isNull);
      expect(c.read(syncProvider).devices.map((d) => d.id), contains('new'));
    });

    test('private listening loads and toggles', () async {
      final api = FakeApi();
      final c = _container(api);
      final ctrl = c.read(privateListeningProvider.notifier);
      expect(c.read(privateListeningProvider), isNull);
      await ctrl.load();
      expect(c.read(privateListeningProvider), isFalse);
      await ctrl.toggle();
      expect(c.read(privateListeningProvider), isTrue);
      expect(api.calls, ['private true']);
    });
  });

  group('widgets', () {
    testWidgets('devices dialog shows code, devices and pairs by code', (tester) async {
      final api = FakeApi();
      await tester.pumpWidget(_host(api, const SizedBox(width: 600, height: 800, child: DevicesDialog())));
      await tester.pumpAndSettle();
      expect(find.text('KQWXZP'), findsOneWidget);
      expect(find.text('laptop'), findsOneWidget);
      expect(find.byTooltip('Online'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('pair-code-field')), 'zz zzzz');
      expect(find.text('ZZZZZZ'), findsOneWidget, reason: 'auto-uppercase, letters only');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No device with that code'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('pair-code-field')), 'ghjklm');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('phone-pc'), findsOneWidget);

      await tester.tap(find.byTooltip('New code'));
      await tester.pumpAndSettle();
      expect(find.text('ABCDEF'), findsOneWidget);

      await tester.tap(find.text('Sync now'));
      await tester.pump();
      expect(api.calls, contains('run'));
      expect(find.text('Syncing…'), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // stops the poll timer
    });

    testWidgets('devices dialog polls only while open', (tester) async {
      final api = FakeApi();
      await tester.pumpWidget(_host(api, const SizedBox(width: 600, height: 800, child: DevicesDialog())));
      await tester.pump();
      await tester.pump(DevicesDialog.pollEvery);
      final whileOpen = api.calls.where((c) => c == 'devices').length;
      expect(whileOpen, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(DevicesDialog.pollEvery * 3);
      expect(api.calls.where((c) => c == 'devices').length, whileOpen);
    });

    testWidgets('devices button hides on old backends; private toggle flips', (tester) async {
      final api = FakeApi(supported: false);
      late WidgetRef ref;
      await tester.pumpWidget(_host(
        api,
        Consumer(builder: (context, r, _) {
          ref = r;
          return const SizedBox(
              width: 256, child: Column(children: [DevicesButton(), PrivateListeningToggle(collapsed: false)]));
        }),
      ));
      expect(find.byTooltip('Devices'), findsOneWidget);
      expect(find.text('Private listening'), findsNothing, reason: 'hidden until loaded');
      await ref.read(syncProvider.notifier).load();
      api.supported = true;
      await ref.read(privateListeningProvider.notifier).load();
      await tester.pump();
      expect(find.byTooltip('Devices'), findsNothing);
      expect(find.text('OFF'), findsOneWidget);
      await tester.tap(find.text('Private listening'));
      await tester.pump();
      expect(find.text('ON'), findsOneWidget);
      expect(api.calls, contains('private true'));
    });
  });
}
