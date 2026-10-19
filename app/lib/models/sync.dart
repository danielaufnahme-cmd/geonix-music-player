/// This device as seen by the sync feature (`this_device` in the API).
class ThisDevice {
  const ThisDevice({required this.id, required this.name, required this.code});

  final String id;
  final String name;

  /// 6-letter pairing code another device types in.
  final String code;

  factory ThisDevice.fromJson(Map<String, dynamic> j) => ThisDevice(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        code: j['code'] as String? ?? '',
      );
}

/// A paired device.
class SyncDevice {
  const SyncDevice({
    required this.id,
    required this.name,
    this.address = '',
    this.online = false,
    this.lastSyncAt,
    this.lastError,
  });

  final String id;
  final String name;
  final String address;
  final bool online;
  final DateTime? lastSyncAt;
  final String? lastError;

  factory SyncDevice.fromJson(Map<String, dynamic> j) => SyncDevice(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        address: j['address'] as String? ?? '',
        online: j['online'] == true,
        lastSyncAt: DateTime.tryParse(j['last_sync_at'] as String? ?? '')?.toLocal(),
        lastError: (j['last_error'] as String?)?.trim().isEmpty ?? true ? null : j['last_error'] as String,
      );
}

/// `GET /api/sync/devices`.
class SyncStatus {
  const SyncStatus({required this.thisDevice, this.devices = const [], this.syncing = false});

  final ThisDevice thisDevice;
  final List<SyncDevice> devices;
  final bool syncing;

  factory SyncStatus.fromJson(Map<String, dynamic> j) => SyncStatus(
        thisDevice: ThisDevice.fromJson((j['this_device'] as Map?)?.cast<String, dynamic>() ?? const {}),
        devices: [
          for (final d in (j['devices'] as List?) ?? const []) SyncDevice.fromJson((d as Map).cast<String, dynamic>()),
        ],
        syncing: j['syncing'] == true,
      );

  SyncStatus copyWith({ThisDevice? thisDevice, List<SyncDevice>? devices, bool? syncing}) => SyncStatus(
        thisDevice: thisDevice ?? this.thisDevice,
        devices: devices ?? this.devices,
        syncing: syncing ?? this.syncing,
      );
}

/// One SSE `sync` event: `{"state","device","done","total","message"}`.
class SyncEvent {
  const SyncEvent({required this.state, this.device = '', this.done = 0, this.total = 0, this.message = ''});

  /// "started", "progress", "done" or "error".
  final String state;
  final String device;
  final int done;
  final int total;
  final String message;

  bool get finished => state == 'done' || state == 'error';
  bool get isError => state == 'error';

  /// 0..1, or null when the total is not known yet.
  double? get fraction => total > 0 ? (done / total).clamp(0.0, 1.0) : null;

  factory SyncEvent.fromJson(Map<String, dynamic> j) => SyncEvent(
        state: j['state'] as String? ?? 'progress',
        device: j['device'] as String? ?? '',
        done: (j['done'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        message: j['message'] as String? ?? '',
      );
}
